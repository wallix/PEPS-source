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

module SidebarView {

  private function log(msg) { Log.notice("SidebarView: ", msg) }

  function icon(id, name, title, icon, string act, onclick) {
    classes = active(act == name)
    <dt class={classes}><a class="fa fa-2x fa-{icon}" title="{title}"
        onclick={onclick}
        data-placement="right" rel="tooltip">
      <div id="{id}_badge" class="badge_holder pull-right"/>
    </a></dt>
  }

  function folder(id, name, title, icon, string act, onclick) {
    classes = active(act == name)
    <dt class={classes}>
      <a title={title} onclick={onclick}>
        <i class="fa fa-{icon}"/>
        <span>{title}</span>
        <div id="{id}_badge" class="badge_holder"/>
      </a>
    </dt>
  }

  /** Return the appropriate renderer. */
  function render(view, id, name, title, ficon, string act, onclick) {
    match (view) {
      case {icons}: icon(id, name, title, ficon, string act, onclick)
      case {folders}:  folder(id, name, title, ficon, string act, onclick)
    }
  }

  // /** Create a clickable item. */
  // function item(Sidebar.view view, string name, string class, string title, string active, (Dom.event -> void) onclick) {
  //   match (view) {
  //     case {icons}: icon(name, class, title, active, onclick)
  //     case {folders}: folder(name, class, title, active, onclick)
  //   }
  // }

  /** The ID of the container of the 'NEW' button. */
  action_id = "new_action"

  /** Return the class (["active"] if so, else []). */
  private function active(bool act) { if (act) ["active"] else [] }

  /** Create a inert header. */
  function header(string title) {
    <li class="header">
      <a data-placement="right">{title}</a>
    </li>
  }

  private view_to_string = function {
    case {icons}: "icons_view"
    case {folders}: "folders_view"
  }

  private function action_button(options, text, action, id) {
    link = match (options.view) {
      case {icons}:
        <a class="fa fa-2x fa-plus-circle" title="{text}"
            onclick={action}
            data-placement="right" rel="tooltip"/>
      case {folders}:
        <a title="{text}" class="btn btn-success"
            onclick={action}>
          {text}</a>
    }
    <div class="sidebar-btn">
      <div id="{id}">
        { link }
      </div>
    </div>
  }

  /** Structured sidebar content for mode */
  function selector(state, mode, options) {
    match (mode) {
      case {messages: box}: MessageView.Sidebar.build(state, options, Mode.active(mode))
      case ~{people}: PeopleView.Sidebar.build(state, options, people)
      case ~{files}: FileView.Sidebar.build(state, options, files)
      case ~{admin}: AdminView.Sidebar.build(state, options, admin)
      case ~{settings}: SettingsView.Sidebar.build(state, options, settings)
      case ~{dashboard}: Dashboard.Sidebar.build(state, options, none)
      default: []
    }
  }

  /** Patch default options with user preferences. */
  // private function apply_options(Login.state state, Sidebar.options opts) {
  //   view = SettingsController.view(state.key)
  //   ~{ opts with view }
  // }

  // element: renders the HTML of one element of the sidebar
  function element(options, Sidebar.element element, string act) {
    match (element) {
      case ~{text, action, id}: action_button(options, text, action, id)
      case ~{content}: content
      case ~{separator, button}: <dd class="sidebar-header"><span class="sidebar-title">{separator}</span>{Option.default(<></>, button)}</dd>
      case ~{name, id, title, icon, onclick}: render(options.view, id, name, title, icon, act, onclick)
    }
  }

  private function dl_elements(options, items, active) {
    <dl class="list-unstyled {view_to_string(options.view)}">
      { if (options.search)
          <dd class="search">,
            <a href="#search" class="fa fa-search hide" title="{@i18n("Search results")}"
               data-placement="right" rel="tooltip"></a>
          </dd>
        else <></> }
      { List.fold(`<+>`, List.rev_map(element(options, _, active), items), <></>) }
      <dd><div id=#progress_bar class="progress_bar"/></dd>
    </dl>
  }

  // elements: render the list of sidebar items
  // CHECK: login check here?
  private function elements(Login.state state, Sidebar.options options, items, string active) {
    if (not(Login.is_logged(state))) <></>
    else
      match (items) {
        case ~{~hd: ~{text, action, id}, tl}:
          element(options, hd, active) <+>
          dl_elements(options, tl, active)
        default: dl_elements(options, items, active)
      }
  }

  protected function content(Login.state state, Mode.t mode) {
    options = {
      Sidebar.default_options with
      view: SettingsController.view(state.key)
    }
    items = selector(state, mode, options)
    elements(state, options, items, Mode.active(mode))
  }

  /** Build the sidebar. */
  protected function build(Login.state state, Mode.t mode) {
    // 'Share' mode must be identified at this point to avoid building an empty sidebar.
    // Same with license activation page.
    if (
      not(Login.is_logged(state)) || Mode.is_share(mode)
    ) <></>
    else <div id=#sidebar class="sidebar" onready={function(_) { Notifications.Badge.update(mode) }}>{content(state, mode)}</div>
  }

  @async
  exposed function refresh(state, urn) {
    #sidebar = content(state, urn.mode)
    Notifications.Badge.update(urn.mode)
  }

}
