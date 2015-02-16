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
      case {failure:_}: void
    }
  }
  exposed @async function open(Team.key key, super) {
    state = Login.get_state()
    #team_viewer = build_team_panes(state, Team.get(key), super)
    TeamController.open(key, open_callback(state, super, _))
  }
  client function do_open(Team.key key, super, _) { open(key, super) }

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

  /** {2} Create a new team. */

  client @async function create_callback(res) {
    match (res) {
      case {success: html}:
        #team_viewer = html
        // Extract team selection from tree view, and set as default value.
        parent =
          Treeview.selected_node(#teams_tree) |>
          Option.bind(function(node) { Team.get(Treeview.identifier(node)) }, _)
        parentkey = Option.map(_.key, parent)
        ClientReference.set(parent_selection, parentkey)
        #parent_selection = team_label(parent)

      case {failure: e}:
        Notifications.error(@i18n("Team creation"), <>{e}</>)
    }
  }
  exposed @async function create(super) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      create_callback({failure: Content.login_please})
    else {
      html = build_form_tab(state, none, super)
      create_callback({success: html})
    }
  }
  client function do_create(super, Dom.event _evt) { create(super) }

  /**
   * {2 Edit an existing team.}
   */

  client @async function edit_callback(res) {
    match (res) {
      case {success: html}:
        #team_viewer = html
      case {failure: _}:
        void
    }
  }
  exposed @async function edit(Team.key d, super) {
    state = Login.get_state()
    match (Team.get(d)) {
      case {none}: edit_callback({failure: @i18n("Team Not found")})
      case {some: team}:
        html = build_team_panes(state, some(team), super)
        edit_callback({success: html})
    }
  }
  client function do_edit(Team.key d, super, _) { edit(d, super) }

  /** {2} Team deletion. */

  client @async function delete_callback(super, res) {
    match (res) {
      case {success}:
        refresh(super)
        #team_viewer = <></>
      case {failure: e}:
        Notifications.error(@i18n("Failed to delete team"), <>{e}</>)
    }
  }
  client function do_delete(Team.key d, string name, super, _) {
    if (d != "" &&
      Client.confirm(@i18n("Are you sure you want to delete team '{name}'?")))
      TeamController.Async.delete(d, delete_callback(super, _))
  }

  /**
   * {2 Save modifications.}
   */

  client @async function save_callback(super, res) {
    match (res) {
      case {success: id}:
        refresh(super)
        edit(id, super)
      case {failure: e}:
        Notifications.error(AppText.Save_failure(), <>{e}</>)
    }
  }
  client function do_save(User.key _key, option(Team.key) d, super, Dom.event _evt) {
    name = Utils.sanitize( Dom.get_value(#team_name) )
    descr = String.trim( Dom.get_value(#team_description) )
    parent = ClientReference.get(parent_selection)
    TeamController.Async.save(d, parent, name, descr, save_callback(super, _))
  }

  /**
   * {1 View elements.}
   */

  /**
   * Make a team label.
   */
  protected function build_team(Team.t team, bclick, onclick) {
    teamid = Random.string(10)
    bclick =
      match (bclick) {
        case {some: bclick}:
          bclick(teamid, team, _)
        default: ignore
      }
    delbtn =
      match (onclick) {
        case {some: onclick}:
          btnid = Random.string(10)
          <a id="{btnid}" onclick={onclick(teamid,_)}
              class="fa fa-times"
              title="{AppText.remove()}"></a>
        case {none}:
          <></>
      }

    <span id="{teamid}" onclick={bclick}>
        <span class="name label label-{team.color}">
          {team.name}{delbtn}
        </span>
    </span>
  }

  private function list(list('a)) segment(list('a) l, int n) {
    recursive function aux(l) {
      match (List.split_at(l,n)) {
      case ([],[]): []
      case (l1,[]): [l1]
      case (l1,l2): [l1|aux(l2)]
      }
    }
    aux(l)
  }

  function xhtml layout_teams(list(Team.t) teams, click, extras) {
    if (List.is_empty(teams))
      match (extras) {
        case []: <></>
        case [extra]: <>{extra}</>
        default: WB.List.unstyled(extras)
      }
    else {
      teams =
        List.map(function (team) { build_team(team, {none}, click(team)) }, teams)
        |> List.append(_, extras)
        // |> segment(_, 3)
      // rows =
      //   List.map(function (row) {
      //     WB.Grid.row(List.map(function (team) { {span:4, offset:{none}, content:team} },row))
      //   },teams)
      WB.List.unstyled(teams)
    }
  }

  /** {2} Parent selection. */

  client function select_parent_callback(team) {
    team = Team.idofs(team)
    ClientReference.set(parent_selection, some(team))
    #parent_selection = team_label(Team.get(team))
  }
  client function do_select_parent(state, Dom.event evt) {
    TeamChooser.create({
      title: @i18n("Select parent team"),
      action: select_parent_callback,
      user: none, excluded: []
    })
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
      {build_form_tab(state, team, super)}
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
    teamlist =
      List.map(function(team) {
        key = team.key
        name = team.name
        content = <span class="name label label-{team.color}" onclick={do_open(key, super, _)}>{team.name}</span>
        (content, (function(e) { Log.info("action", "item: {key}:{name}") }))
      }, teams)
    ListGroup.make_action(teamlist, AppText.no_teams())
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

  /**
   * Actions to perform after construction of the form.
   */
  //function form_ready(Dom.event _evt) {
  //  void
  //}

  /**
   * Build the team edition/creation tab.
   */
  function build_form_tab(Login.state state, option(Team.t) team, super) {
    <>
      {build_team_view(state, team, super)}
    </>
  }

  /**
   * Build a label with the name and color of the given team.
   */
  function team_label(team) {
    match (team) {
      case {some: team}:
        <span class="name label label-{team.color}">{team.name}</span>
      default:
        <span class="name label label-default">root</span>
    }
  }

  /**
   * Build the edition / creation form.
   */
  protected function build_team_view(Login.state state, option(Team.t) team, super) {
    is_admin = super && Login.is_admin(state)
    // Previous inputs.
    (name, descr) =
      match (team) {
        case {some: team}:
          ({some: team.name}, team.description)
        case {none}:
          ({none}, "")
      }
    // Parent selection.
    selparent =
      match (team) {
        case {none}:
        <div class="form-group">
          <label class="control-label">{@i18n("Parent team")}</label>
          <div id=#parent_selection onclick={do_select_parent(state, _)}
            data-toggle="context" data-target="#context_menu_content">
              {team_label({none})}
          </div>
        </div>
        default: <></>
      }
    delete_btn =
      match (team) {
        case {some: team}:
          <div class="pull-right">
            <a class="btn btn-sm btn-default" onclick={do_delete(team.key, team.name, super, _)}>
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
          callback: do_save(state.key, Option.map(_.key, team), super, _)},
        [{primary}]
      )
    action = some(do_save(state.key, name, super, _))
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
