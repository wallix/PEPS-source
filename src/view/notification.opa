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


package com.mlstate.webmail.view

module Notifications {

  private function log(msg) { Log.notice("Notifications: ", msg) }

  /** {1} Badges. */

  module Badge {

    /** Create a bootstrao badge. */
    both function make(level, importance) {
      // nb = if nb > 100 then "100+" else "{nb}"
      if (level < 1) <></>
      else
        WBootstrap.Badge.make(<>{level}</>, importance) |>
        WBootstrap.pull_right(_)
    }

    private function insertone(Notification.badge badge) {
      log("Badge.insert: {badge}")
      #{badge.id} = make(badge.level, badge.importance)
    }

    /** Insert a notifications badge. */
    client function void insert(Notification.badges badges) {
      // urn = URN.get()
      // if (Mode.equiv(urn.mode, badges.mode))
      List.iter(insertone, badges.badges)
      // Update title.
      if (badges.global > 0)
        Client.setTitle("({badges.global}) - {AppText.app_title()}")
      else Client.setTitle(AppText.app_title())
      // Show HTML5 notification.
      notify(badges.mode, badges.global)
    }

    /** Fetch the badges associated with the current urn mode. */
    exposed function fetch(Mode.t mode) {
      // Fetch. Only messages may have badges for now.
      match (mode) {
        case {messages: _}: MessageController.badges(true)
        default: MessageController.badges(false)
      }
    }

    /** Fetch the badges and update the view. */
    @async function update(Mode.t mode) { fetch(mode) |> insert }

    /**
     * Keep the last global badges. Used to determine when to throw in new
     * HTML5 notifications. Associates each mode with the last notified
     * badge.
     */
    client private globalBadges = ClientReference.create(stringmap(int) StringMap.empty)

    /**
     * Three steps:
     *  - compare the new count with the stored one.
     *  - call a HTML5 notification if new number if greater.
     *  - update reference if needed.
     */
    private function notify(Mode.t mode, int count) {
      if (count > 0) {
        badges = ClientReference.get(globalBadges)
        mode = Mode.class(mode)
        // Whether to show an HTML5 notification.
        (donotify, doupdate) = match (StringMap.get(mode, badges)) {
          case {some: oldcount}: (oldcount < count, oldcount != count)
          default: (true, true)
        }
        // Show HTML5 notification.
        if (donotify)
          HTML5_Notifications.simple(
            AppText.new_mails_title(),
            @i18n("{count} new mails in your Inbox"),
            some("/favicon.ico")
          )
        // Update reference.
        if (doupdate)
          ClientReference.set(globalBadges, StringMap.add(mode, count, badges))
      }
    }

  } // END BADGE

  /** {1} Build and display notifications. */

  both function build(title, description, priority) {
    WBootstrap.Alert.make(
      {alert: ~{title, description}, closable: true},
      priority
    )
  }

  /** {1} Notification handler. */

  client function handler(message) {
    match (message) {
      // Load the received message into the view
      // (message list + thread), only if the mode
      // is /inbox.
      case {received: mid}:
        if (Mode.equiv(URN.get().mode, {messages: {inbox}}))
          MessageView.Message.load(mid)
      // Load received badges into the view.
      case ~{badges}:
        log("handler: received badges")
        Badge.insert(badges)
      // Update the progress bar located in the sidebar.
      case {fetching: (name, percent)}:
       #progress_bar =
        <div class="progress progress-info progress-striped active" title="{@i18n("Fetching {name} mails...")}">
          <div class="bar" style={[Css_build.width(~{ percent })]}/>
        </div>
      case {fetched}:
        Dom.remove_content(#progress_bar)
      case {error: (t, msg)}:
        Notifications.error(t, XmlConvert.of_alpha(msg))
    }
  }

  /** {2} General notification builder. */

  /** Insert the notification in the proper area. */
  client @expand function notify(string area, title, descr, priority) {
    #{area} = build(title, descr, priority)
  }

  /** {2} Notifications appearing in the main container. */

  /** Shortcuts for different priorities. The area is always the main one in these cases. */
  client @expand function error(title, descr) { notify("notification_area", title, descr, {error}) }
  client @expand function warning(title, descr) { notify("notification_area", title, descr, {warning}) }
  client @expand function success(title, descr) { notify("notification_area", title, descr, {success}) }
  client @expand function info(title, descr) { notify("notification_area", title, descr, {info}) }


  client @expand function loading() { warning(AppText.loading_title(), <>...</>) }
  @async client function clear() { Dom.remove_content(#notification_area) }
  @async client function clear_loading() {
    if (String.contains(Dom.get_text(#notification_area), AppText.loading_title()))
      Dom.remove_content(#notification_area)
  }

}
