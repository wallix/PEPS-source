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

/**
 * Current parent selection.
 */
client reference(option(Team.key)) parent_selection = ClientReference.create(none)

module TeamView {

  private function log(msg) { Log.info("TeamView:", msg) }

  /** {1} Callbacks. */

  /** {2} Open the team edit pane. */

  protected @async function open_callback(state, super, res) {
    match (res) {
      case {success: {~teams}}:
        Dom.transform([#pane_users_content = build_teams(teams, super)])
      case {success: ~{users}}:
        page = UserController.highlight(users) |> Iter.to_list |> UserController.page
        html = UserView.build_page(state, page, none, User.emptyFilter)
        Dom.transform([#pane_users_content = html])
      case {failure: _}: void
    }
  }
  exposed @async function open(Team.key key, super) {
    state = Login.get_state()
    #team_viewer = build_team_panes(state, Team.get(key), super)
    TeamController.open(key, open_callback(state, super, _))
  }
  client function do_open(Team.key key, super, _evt) { open(key, super) }

  /** {2} Refresh the team list. */

  client @async function refresh_callback(res) {
    match (res) {
      case {success: html}:
        Dom.transform([#teams_view = html])
      case {failure: _}:
        void
    }
  }
  exposed @async function refresh(super) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      refresh_callback({failure: Content.login_please})
    else {
      html = build_inner(state, super)
      refresh_callback({success: html})
    }
  }

  /** Open the team creation form. */
  client function create(super, Dom.event _evt) {
    html = buildForm(none, super)
    #team_viewer = html
    // Extract team selection from tree view, and set as default value.
    parent =
      Treeview.selected_node(#teams_tree) |>
      Option.bind(function(node) { Team.get(Treeview.identifier(node)) }, _)
    parentkey = Option.map(_.key, parent)
    ClientReference.set(parent_selection, parentkey)
    #parent_selection = smallLabel(parent)
  }

  /** {2} Edit an existing team. */

  client @async function edit_callback(res) {
    match (res) {
      case {success: html}: #team_viewer = html
      case {failure: _}: void
    }
  }
  exposed @async function edit(Team.key team, super) {
    state = Login.get_state()
    if (not(Login.is_admin(state))) edit_callback(Utils.Failure.forbidden())
    match (Team.get(team)) {
      case {some: team}:
        html = build_team_panes(state, some(team), super)
        edit_callback({success: html})
      default: edit_callback(Utils.failure(@intl("Team Not found"), {wrong_address}))
    }
  }

  /** Team deletion. */
  client function delete(Team.key team, string name, super, _) {
    if (team != "" && Client.confirm(@intl("Are you sure you want to delete team '{name}'?")))
      TeamController.Async.delete(team, function {
        // Client side.
        case {success}:
          refresh(super)
          #team_viewer = <></>
        case ~{failure}:
          Notifications.error(@intl("Failed to delete team"), <>{failure.message}</>)
      })
  }

  /** Save modifications. */
  client function save(option(Team.key) team, super, Dom.event _evt) {
    name = Utils.sanitize( Dom.get_value(#team_name) )
    descr = String.trim( Dom.get_value(#team_description) )
    parent = ClientReference.get(parent_selection)
    TeamController.Async.save(team, parent, name, descr, function {
      // Client side.
      case {success: id}:
        refresh(super)
        edit(id, super)
      case ~{failure}:
        Notifications.error(AppText.Save_failure(), <>{failure.message}</>)
    })
  }

  /** {1} View elements. */

  /** Make a team label. */
  protected function label(Team.t team, bclick, onclick) {
    teamid = Random.string(10)
    bclick =
      match (bclick) {
        case {some: bclick}: bclick(teamid, team, _)
        default: ignore
      }
    delbtn =
      match (onclick) {
        case {some: onclick}:
          btnid = Random.string(10)
          <a id="{btnid}" onclick={onclick(teamid,_)}
              class="fa fa-times"
              title="{AppText.remove()}"></a>
        default: <></>
      }

    <span id="{teamid}" onclick={bclick}>
      <span class="name label label-{team.color}">
        {team.name}{delbtn}
      </span>
    </span>
  }

  /** Build a label with the name and color of the given team. */
  function smallLabel(option(Team.t) team) {
    match (team) {
      case {some: team}: <span class="name label label-{team.color}">{team.name}</span>
      default: <span class="name label label-default">root</span>
    }
  }

  /** Layout a list of teams, formatted as labels. */
  function xhtml layout(list(Team.t) teams, click, extras) {
    if (teams == [])
      match (extras) {
        case []: <></>
        case [extra]: <>{extra}</>
        default: WB.List.unstyled(extras)
      }
    else
      List.map(function (team) { label(team, none, click(team)) }, teams) |>
      List.append(_, extras) |>
      WB.List.unstyled
  }

  /** {1} Construction of the team form. */

  /** {2} Creation of the panes. */

  function team_tabs(super) {
    <div class="pane-heading">
      <ul class="nav nav-pills">
        <li class="active"><a href="#team-pane" data-toggle="tab">{AppText.team()}</a></li>
        {if (super) <li><a href="#users-pane" data-toggle="tab">{AppText.users()}</a></li>
         else       <li><a href="#messages-pane" data-toggle="tab">{AppText.messages()}</a></li>}
      </ul>
    </div>
  }
  function team_pane_edit(state, team, super) {
    <div class="tab-pane active" id=#team-pane>
      {buildForm(team, super)}
    </div>
  }
  function team_pane_users(state) {
    <div class="tab-pane pane-wrap" id=#users-pane>
      <div id=#users_list class="users_list col-md-4 pane-inner-left">
        <div id=#pane_users_content></div>
      </div>
      <div id=#user_viewer class="col-md-8 pane-inner-right"/>
    </div>
  }
  function team_pane_messages(state) {
    <div class="tab-pane" id=#messages-pane>
      <div id=#pane_messages_content class="pane-wrap">
      </div>
    </div>
  }
  function build_team_panes(state, option(Team.t) team, super) {
    <>
      {team_tabs(super)}
      <div id=#team-panes class="tab-content">
        {team_pane_edit(state, team, super)}
        { if (super) team_pane_users(state)
          else team_pane_messages(state) }
      </div>
    </>
  }


  protected function build_teams(list(Team.t) teams, bool super) {
    List.map(function(team) {
      key = team.key
      name = team.name
      content = <span class="name label label-{team.color}">{team.name}</span>
      // Return list item with onclick handler.
      (content, do_open(key, super, _))
    }, teams) |>
    ListGroup.make(_, AppText.no_teams())
  }

  /**
   * Produce the SERIALIZED list of nodes forming the forest whose roots are the given
   * teams.
   */
  exposed function build_tree_data(list(Team.t) teams) {
    nodes = List.map(Team.buildNode(_, []), teams) |> List.flatten
    OpaSerialize.serialize(nodes)
  }

  /**
   * Build the treeview component.
   */
  client function build_tree(string nodes, bool super) {
    function callback(evt, node) { do_open(Treeview.identifier(node), super, evt) }
    Treeview.build_serialized(#teams_tree, nodes, callback)
    Treeview.options(#teams_tree, {expandIcon: "fa fa-chevron-right", collapseIcon: "fa fa-chevron-down"})
  }

  /** Parent selection. */
  client function selectParent(_evt) {
    function action(team) {
      team = Team.idofs(team)
      ClientReference.set(parent_selection, some(team))
      #parent_selection = smallLabel(Team.get(team))
    }
    TeamChooser.create({
      title: @intl("Select parent team"),
      ~action, user: none, excluded: []
    })
  }

  /** Build the edition / creation form. */
  both function buildForm(option(Team.t) team, super) {
    // Previous inputs.
    (name, descr) =
      match (team) {
        case {some: team}: (some(team.name), team.description)
        case {none}: (none, "")
      }
    // Parent selection.
    selparent =
      match (team) {
        case {none}:
        <div class="form-group">
          <label class="control-label">{@intl("Parent team")}</label>
          <div id=#parent_selection onclick={selectParent}
            data-toggle="context" data-target="#context_menu_content">
              {smallLabel(none)}
          </div>
        </div>
        default: <></>
      }
    delete_btn =
      match (team) {
        case {some: team}:
          <div class="pull-right">
            <a class="btn btn-sm btn-default" onclick={delete(team.key, team.name, super, _)}>
              <i class="fa fa-trash-o"/> {AppText.delete()}
            </a>
          </div>
        case {none} ->
          <></>
      }
    heading =
      match (team) {
        case {some: team}:
          AppText.edit_team(team.name)
        case {none} ->
          AppText.create_team()
      }
    save_text =
      if (Option.is_some(team)) AppText.save()
      else AppText.create()
    save_button =
      WB.Button.make(
        { button: <>{save_text}</>,
          callback: save(Option.map(_.key, team), super, _)},
        [{primary}]
      )
    action = some(save(name, super, _))
    Form.wrapper(
      <div class="pane-heading">
        {delete_btn}
        <h3 class="pull-left">{heading}</h3>
      </div> <+>
      selparent <+>
      Form.line(~{Form.Default.line with
        label: AppText.name(), id: "team_name", class: ["col-md-8"], value: name ? "", action
      }) <+>
      Form.line(~{Form.Default.line with
        label: AppText.description(), id: "team_description", class: ["col-md-8"], value: descr, action
      }) <+>
      <div class="form-group">
        {save_button}
      </div>
    , false)
  }

  /**
   * Assemble all the components.
   */
  protected function build_inner(Login.state state, bool super) {
    teams =
      if (Login.is_super_admin(state)) Team.roots()
      else User.get_admin_teams(state.key)
    nodes = build_tree_data(teams)
    <div id=#teams_list class="pane-left">
      <div class="pane-heading">
        <h3>{AppText.teams()}</h3>
      </div>
      <div id=#teams_tree onready={function(_) { build_tree(nodes, super) }}>
        <span class="empty-text">{AppText.no_teams()}</span>
      </div>
    </div>
    <div id=#team_viewer class="pane-right">
    </div>
  }

  protected function build(Login.state state, bool super) {
    Content.check_admin(state,
      <div id=#teams_view>{build_inner(state, super)}</div>
    )
  }

}
