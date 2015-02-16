/*
 * PEPS is a modern collaboration server
 * Copyright (C) 2015 MLstate
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


package com.mlstate.webmail.controller


/** Generic badge type. */
type Notification.badge = {
  string id, // Dom id.
  int level, // Badge level.
  WBootstrap.BadgeLabel.importance importance // Badge category.
}
type Notification.badges = {
  Mode.t mode, // The mode associated with these badges.
  list(Notification.badge) badges, // List of local badges.
  int global // Update the page title.
}

type Notification.Client.message =
  { Message.id received } or // Notification for received messages.
  { Notification.badges badges } or
  { (string, xhtml) error } or
  { (string, float) fetching } or
  { fetched }

type Notification.Server.message =
  { (User.key, channel(Notification.Client.message)) connection } or
  { (User.key, channel(Notification.Client.message)) disconnection } or
  { (User.key, Notification.Client.message) transmit } or
  { (User.key, -> void, -> void) call } or
  { (User.key, string, xhtml) error }

module Notification {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[Notification]", msg) }

  nobadges = Notification.badges {
    global: 0,
    badges: [],
    mode: {messages: {inbox}}
  }

  /** {1} Cloud. */

  protected cloud = channel(Notification.Server.message) Session.cloud("notifications", StringMap.empty, handler)

  /** Server handler. */
  function handler(state, message) {
    match (message) {
      case {transmit: (key, message)}:
        match (StringMap.get(key, state)) {
          case {some: channels}:
            Session.send_all(channels, message)
            {unchanged}
          default: {unchanged}
        }
      case {connection: (key, channel)}:
        match (StringMap.get(key, state)) {
          case {some: channels}: {set: StringMap.add(key, [channel|channels], state)}
          default: {set: StringMap.add(key, [channel], state)}
        }
      case {disconnection: (key, channel)}:
        match (StringMap.get(key, state)) {
          case {some: channels}:
            channels = List.remove(channel, channels)
            if (channels == []) {set: StringMap.remove(key, state)}
            else {set: StringMap.add(key, channels, state)}
          default: {unchanged}
        }
      case {call: (key, ifpresent, ifabsent)}:
        present =
          match (StringMap.get(key, state)) {
            case {some: channels}: channels != []
            default: false
          }
        Scheduler.push(function () {
          if (present) ifpresent()
          else ifabsent()
        })
        {unchanged}
      case {error: (key, title, msg)}:
        match (StringMap.get(key, state)) {
          case {some: channels}:
            Session.send_all(channels, {error: (title, msg)})
            {unchanged}
          default: {unchanged}
        }
    }
  }

  /** {1} Public functions. */

  /** Connect or disconnect a user to a channel. */
  protected function register(key, channel) {
    // Automatically remove the user user's channel on disconnection.
    Session.on_remove(channel, function () { unregister(key, channel) })
    Session.send(cloud, {connection: (key, channel)})
  }
  protected function unregister(key, channel) {
    Session.send(cloud, {disconnection: (key, channel)})
  }
  protected @async function error(User.key key, string title, xhtml msg) {
    Session.send(cloud, {error: (key, title, msg)})
  }
  protected @async function call(key, ifpresent, ifabsent) {
    Session.send(cloud, {call: (key, ifpresent, ifabsent)})
  }

  /**
   * Keeps the context of badges broadcast by one user.
   * Newly broadcast badges are filtered depending on the badges already sent, and
   * the list is updated accordingly.
   *
   * TODO implement. Caution: this will store badges, whoever the user is receiving them.
   *  So just storing the last broadcast badges is prone to error.
   */
  // private broadcastBadges = UserContext.make(list(Notification.badge) [])

  module Broadcast {

    /** Broadcast user badges. */
    protected @async function badges(key) {
      badges = FolderController.badges(key, true)
      Session.send(cloud, {transmit: (key, ~{badges})})
    }

    /** Notify receivers of a message. */
    protected @async function received(mid, owners) {
      List.iter(function (key) {
        // Team notifications are propagated to team users.
        if (Team.key_exists(key))
          User.get_team_users([key]) |>
          Iter.iter(function (user) {
            Session.send(cloud, {transmit: (user.key, {received: mid})})
            badges(user.key)
          }, _)
        else {
          Session.send(cloud, {transmit: (key, {received: mid})})
          badges(key)
        }
      }, owners)
    }

  } // END BROADCAST

}
