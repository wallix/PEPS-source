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


package com.mlstate.webmail.model

/** Specificies the way topbar elements are displayed. */
type Icon.display = {normal} or {hide} or {int priority}
type Topbar.display =
  { Icon.display icon,    // Icon display.
    App.display content } // Content display.

/** Type of callback. */
type Topbar.callback =
  {Path.t update} or  // Local update (the mode is taken from the topbar item).
  {string url}        // Open extern url.

/**
 * Topbar items.
 * TODO: use a structured type for path.
 */
type Topbar.item = {
  Mode.t mode,                  // Associated mode.
  string icon,                  // Topbar icon.
  Topbar.display display,       // Display settings.
  string title
}

/** User topbar preferences. */
type Topbar.preference = { Mode.t mode, Topbar.display display }
type Topbar.preferences = list(Topbar.preference)

module Topbar {

  /** Shortcut for a fullscreen display with a specified icon prority. */
  @expand function fullscreen(int priority) {
    {content: {fullscreen}, icon: ~{priority}}
  }

  /** Convert an application setting to a topbar item. */
	@expand function makeitem(app) {
		{ mode: {app: app.name, active: ""},
      display: {content: app.display, icon: {normal}},
      icon: app.icon ? "fa-cube",
      title: app.name }
	}

  /**
   * Return the equivalent priority of topbar elements. Normal elements
   * have the lowest priority.
   */
  function priority(Topbar.item item) {
    match (item.display.icon) {
      case ~{priority}: priority
      default: Limits.max_int
    }
  }

  /** Return true iff the element is hidden. */
  function hidden(Topbar.item item) {
    item.display.icon == {hide}
  }

  /** Return true iff the element is visible. */
  function visible(Topbar.item item) {
    item.display.icon != {hide}
  }

  /** Default topbar settings. */
  server function core() {[
    {mode: {dashboard: "all"}, display: fullscreen(0), icon: "fa-home", title: AppText.dashboard()},
    {mode: {messages: {inbox}}, display: fullscreen(1), icon: "fa-envelope", title: AppText.messages()},
    {mode: {files: "files"}, display: fullscreen(2), icon: "fa-files", title: AppText.files()},
    {mode: {people: "contacts"}, display: fullscreen(3), icon: "fa-users", title: AppText.people()}
  ]}

  server function admin() {[
    {mode: {admin: "settings"}, display: fullscreen(4), icon: "fa-cog", title: AppText.admin()}
  ]}

  /**
   * List the topbar items with their preferences.
   *
   * @param super super admin mode.
   * @param preferences user preferences.
   */
	function items(bool super, preferences) {
		admin = if (super) admin() else []
		apps = List.map(makeitem, App.list())
		items = List.flatten([core(), admin, apps])
    // Add user preferences.
    items = List.rev_map(function (item) {
      match (List.assoc(item.mode, preferences)) {
        case {some: display}: ~{item with display}
        default: item
      }
    }, items)
    // Remove hidden elements.
    items = List.filter(visible, items)
    // Sort by priority.
    List.sort_by(priority, items)
	}

}
