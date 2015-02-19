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

module PeopleView {

  /**
   * Create the sidebar list of user teams, each item linking to the
   * contacts of this team.
   */
  protected function list_team_contacts(Login.state state, view) {
    if (not(Login.is_logged(state))) <></>
    else {
      teams = User.get_min_teams(state.key)
      list =
        List.rev_map(function (team) {
          name = Team.get_name(team) ? ""
          urn = URN.make({people: "contacts"}, ["teams", name])
          onclick = Content.update_callback(urn, _)
          <dt><a class="name" onclick={onclick}>
            <i class="fa fa-lg fa-contact"></i> {String.capitalize(name)}</a></dt>
        }, teams)

      match (view) {
        case {icons}: <>Not implemented for icons</>
        case {folders}:
          <>{ List.fold(`<+>`, list, <></>) }</>
        default: <>Error: view case not possible "{view}"</>
      }
    }

  }

  protected function build(Login.state state, mode, Path.t path) {
    admin = Login.is_admin(state)
    match (mode) {
      case "contacts": ContactView.build(state, path)
      case "users":
        if (admin) UserView.build(state, path)
        else Content.not_allowed_resource
      case "teams":
        if (admin) TeamView.build(state, true)
        else Content.not_allowed_resource
      default: Content.non_existent_resource
    }
  }

  /** Return the action associated with a mode. */
  private function action(string mode) {
    match (mode) {
      case "users":
        [{
          text: {@i18n("New user")},
          action: UserView.build_register,
          id: SidebarView.action_id
        }]
      case "teams":
        [{
          text: {@i18n("New team")},
          action: TeamView.create(true, _),
          id: SidebarView.action_id
        }]
      case "contacts":
        [{
          text: {@i18n("New contact")},
          action: ContactView.create(_),
          id: SidebarView.action_id
        }]
      default: []
    }
  }

  /** {1} Construction of the sidebar. */
  Sidebar.sign module Sidebar {

    function build(state, options, mode) {
      view = options.view
      admin = Login.is_admin(state)
      // Onclick behaviour.
      function onclick(mode, _evt) {
        urn = URN.make({people: mode}, [])
        // SidebarView.refresh(state, urn) => already done in Content.update
        Content.update(urn, false)
      }

      contacts = [
        { name: "contacts", icon: "contact", id: "contacts", title: AppText.contacts(), onclick: onclick("contacts", _) },
        { separator: @i18n("Team Contacts"), button : none},
        { content: PeopleView.list_team_contacts(state, view) }
      ]

      if (admin) {
        List.flatten([
          action(mode),
          [ { name: "users", icon: "user-o", id: "user", title: AppText.users(), onclick: onclick("users", _) },
            { name: "teams", icon: "users-o", id: "users", title: AppText.teams(), onclick: onclick("teams", _) } ],
          contacts
        ])
      }
      else
        List.flatten([
          action(mode),
          contacts
        ])
    }
  } // END SIDEBAR

}
