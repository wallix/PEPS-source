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

module TopbarView {

  /** PEPS logo. */
  function logo() {
    WB.Navigation.brand(
      <>
        <img src="/resources/img/peps-logo.png" class="navbar-logo"/>
        <span class="hidden-xs hidden-sm" title="{Admin.logo()}" id="topbar_logo_name">{Admin.shortLogo()}</>
      </>, some("/"), ignore)
  }

  /** Change the logo. */
  client function setLogo(string logo) {
    #topbar_logo_name = <>{Utils.string_limit(9, logo)}</>
    Dom.set_attribute_unsafe(#topbar_logo_name, "title", logo)
  }

  /** Build the topbar contents. */
  protected function build_generic(nav) { nav }

  /** Empty topbar, for shared resources. */
  protected function empty(state) {
    build_generic(<></>)
  }

  /**
   * Format a topbar item.
   * TODO: preserve last path for each mode?
   */
  function format(Topbar.item item, active) {
    mode = item.mode
    active = if (Mode.equiv(mode, active)) ["active"] else []
    callback = Content.update_callback(URN.make(mode, []), _)

    <li class={active} id={Mode.class(mode)}>
      <a onclick={callback}>
        <span class="fa fa-lg {item.icon}" title="{item.title}" rel="tooltip" data-placement="bottom"></span>
      </a>
      <div id="{Mode.class(mode)}_badge" class="badge_holder"/>
    </li>
  }

  /** Activate to right topbar element. */
  client function activate(Mode.t mode) {
    elt = #{Mode.class(mode)}
    Dom.select_siblings(elt) |> Dom.remove_class(_, "active")
    Dom.add_class(elt, "active")
  }

  protected function build(state, mode) {
    if (Mode.is_share(mode))
      <div id="topbar" class="navbar navbar-fixed-top navbar-inverse">{empty(state)}</div>
    else {
      // TOOD get user preferences.
      login =
        if (Login.is_logged(state)) <div id="login" class="navbar-right">{Login.build(state)}</div>
        else <></>
      items = Topbar.items(Login.is_super_admin(state), [])
      list = List.fold(function (item, list) { list <+> format(item, mode) }, items, <></>)
      contents = build_generic(
        <div class="navbar-header">
          {logo()}<div class="navbar-left nav-search hidden-xs">{SearchView.build(state)}</div>
          {login}<ul class="nav navbar-nav navbar-right nav-icon">{list}</ul>
        </div>
      )
      <div id="topbar" class="navbar navbar-fixed-top navbar-inverse">
        {contents}
      </div>
    }
  }

  /** Change the profile picture. */
  function setProfilePicture(RawFile.id photo) {
    #profile_picture = <img src="/thumbnail/{photo}" class="user-img"/>
  }


}
