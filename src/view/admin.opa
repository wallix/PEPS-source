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

AdminView = {{


  /** Register a new user. */
  @client do_register(callback, _evt) =
    fname = Dom.get_value(#register_first_name) |> String.trim
    lname = Dom.get_value(#register_last_name) |> String.trim
    username = Dom.get_value(#register_username) |> Utils.sanitize
    password = Dom.get_value(#register_password)
    check_password = Dom.get_value(#check_password)
    level = AppConfig.default_level // FIXME
    teams = [] // FIXME
    if (check_password != password) then
      Notifications.error(@i18n("Registration"), <>{@i18n("Passwords do not match.")}</>)
    else
      AdminController.Async.register(fname, lname, username, password, level, teams,
        // Client side.
        | ~{failure} -> Notifications.error(@i18n("Registration Failed"), <>{failure.message}</>)
        | {success= (admin, user)} ->
          do Notifications.success(@i18n("Registration Successful"), <>{@i18n("Congratulations.")}</>)
          match (callback) with
          | {some= callback} -> callback(user)
          | {none} ->
            if admin then Content.reset()
            else
              do Dom.set_value(#loginbox_username, Dom.get_value(#register_username))
              Dom.set_value(#loginbox_password, Dom.get_value(#register_password))
          end
      )

  @server_private
  register(state, callback) =
    if (Admin.only_admin_can_register() && not(Login.is_admin(state))) then <></>
    else
      domain = Admin.get_domain()
      <div id=#register>{
        Form.wrapper(
          <div class="pane-heading">
            <h3>{AppText.register_new_account()}</h3>
          </div> <+>
          Form.line({Form.Default.line with label=@i18n("First name"); id="register_first_name"}) <+>
          Form.line({Form.Default.line with label=@i18n("Last name"); id="register_last_name"}) <+>
          Form.label(@i18n("Username (definitive)"), "register_username",
            <div class="input-group">
              <input id="register_username"
                  class="form-control" type="text"
                  required="required"></input><span class="input-group-addon">@{domain}</span>
            </div>) <+>
          Form.line({Form.Default.line with label=AppText.password(); id="register_password"; typ="password"; required=true}) <+>
          Form.line({Form.Default.line with label=@i18n("Repeat"); id="check_password"; typ="password"; required=true}) <+>
          <div class="form-group">{
            WB.Button.make({button=<>{AppText.register()}</> callback=do_register(callback, _)}, [{primary}])
         }</div>
        , false)
      }
      </div>

  /** {1} General settings (e.g. disconnection timetout, etc.). */

  Settings = {{

    /** Change general settings. */
    @client set(_evt) =
      timeout = Dom.get_value(#disconnection_timeout)
      grace_period = Dom.get_value(#disconnection_grace_period)
      logo = Dom.get_value(#logo_name) |> String.trim
      domain_name = Dom.get_value(#domain_name)
      only_admin_can_register = Dom.is_checked(#only_admin_can_register)
      match (Parser.int(timeout),Parser.int(grace_period)) with
      | ({some=timeout}, {some=grace_period}) ->
        settings = ~{
          disconnection_timeout = timeout
          disconnection_grace_period = grace_period
          domain = String.trim(domain_name)
          logo only_admin_can_register
        }
        AdminController.set_settings(settings,
          // Client side.
          | {success= (timeout, grace_period, domain)} ->
            do TopbarView.setLogo(logo)
            Notifications.success(
              AppText.settings(),
              <>{@i18n("Timeout {timeout} minutes, Grace period {grace_period} seconds, Domain {domain}")}</>
            )
          | {failure= err} -> Notifications.error(AppText.settings(), <>{err}</>)
        )
      | _ -> Notifications.error(AppText.settings(), <>{@i18n("Invalid timeout or grace period")}</>)
      end

    @server_private
    build(state) =
      logo_name = AdminController.get_logo_name()
      domain_name = AdminController.get_domain_name()
      timeout = AdminController.get_timeout()
      grace_period = AdminController.get_grace_period()
      register_enabled = Admin.only_admin_can_register()
      Utils.panel_default(
        Utils.panel_heading("PEPS") <+>
        Utils.panel_body(
          <form role="form">
            <div class="form-group">
              <label>{@i18n("Version")}</label>
              <p class="form-control-static">{peps_tag}</p>
            </div>
            <div class="form-group">
              <label>{@i18n("Hash")}</label>
              <p class="form-control-static">{peps_version}</p>
            </div>
          </form>
        )
      ) <+>
      Utils.panel_default(
        Utils.panel_heading(AppText.settings()) <+>
        Utils.panel_body(
          Form.wrapper(
            Form.line({Form.Default.line with label=@i18n("Logo name"); id="logo_name"; value=logo_name}) <+>
            Form.line({Form.Default.line with label=@i18n("Domain name"); id="domain_name"; value=domain_name}) <+>
            Form.label(
              @i18n("Disconnection timeout (in minutes)"), "disconnection_timeout",
              <input class="form-control" type="number" id=#disconnection_timeout value="{timeout}" min="10"></input>
            ) <+>
            Form.label(
              @i18n("Disconnection grace period (in seconds)"), "disconnection_grace_period",
              <input class="form-control" type="number" id=#disconnection_grace_period value="{grace_period}" min="10"></input>
            ) <+>
            <>
            <div class="form-group">
              <div class="checkbox">
                <label>
                  { if register_enabled
                    then <input type="checkbox" id=#only_admin_can_register checked="checked"/>
                    else <input type="checkbox" id=#only_admin_can_register/>
                  } {@i18n("Only admin can register users")}
                </label>
              </div>
            </div>
            </> <+>
            <div class="form-group">{
              WB.Button.make({button=<>{AppText.save()}</> callback=Settings.set}, [{primary}])
              |> Xhtml.add_attribute_unsafe("data-complete-text", AppText.save(), _)
              |> Xhtml.add_attribute_unsafe("data-loading-text", AppText.saving(), _)
              |> Xhtml.add_id(some("save_prefs_button"), _)
            }</div>
          , false)
      ))

  }} // END SETTINGS


  /** {1} Applications. */

  App = {{

    /** Generic callback. */
    @private @client callback =
      | {failure=msg} -> Notifications.error(AppText.Apps(), <>{msg}</>)
      | _ ->
        do Dom.set_value(#new_app_name, "")
        do Dom.set_value(#new_app_url, "")
        refresh()

    @private @both header =
      <thead><tr>
        <th></th>
        <th>{AppText.name()}</th><th>{AppText.link()}</th>
        <th>{AppText.Key()}</th><th>{AppText.Secret()}</th>
        <th></th>
      </tr></thead>

    /**
     * Validate an application's URL.
     * The provider must be either '*' or a valid
     * http url.
     */
    @private valid_http(addr) =
      match Uri.of_string(addr) with
      | {some=uri} -> Uri.is_valid_http(uri)
      | _ -> false
      end

    /** App creation. */
    @client create(_evt) =
      name = Dom.get_value(#new_app_name)
      url = Dom.get_value(#new_app_url) |> String.trim
      if name != "" && url != "*" && valid_http(url) // && valid_http(provider)
      then AdminController.App.create(name, url, callback)
      else callback({failure=@i18n("Provider is not a valid HTTP address")})

    /** App deletion. */
    @client delete(key, _evt) =
      AdminController.App.delete(key,
        | {failure=msg} -> Notifications.error(AppText.Apps(), <>{msg}</>)
        | _ -> refresh()
      )

    /** Build the list of applications. */
    @both panel(apps) =
      rows = List.fold(app, list ->
        list <+>
        <tr>
          <td><span class="fa fa-lg {app.icon ? "fa-cube"}"></span></td>
          <td>{app.name}</td><td>{app.url}</td>
          <td>{app.oauth_consumer_key}</td><td>{app.oauth_consumer_secret}</td>
          <td><a class="pull-right" onclick={delete(app.oauth_consumer_key, _)}
              rel="tooltip" title={AppText.delete()}>
            <i class="fa fa-trash-o"/>
          </a></td>
        </tr>, apps, <></>)
      body =
        if apps == []
        then <p class="form-control-static">{AppText.No_apps()}</p>
        else
          <table class="table">
            {header}
            <tbody>{rows}</tbody>
          </table>
      panel =
        <div class="panel panel-default">
          <div class="panel-heading">{AppText.Apps()}</div>
          <div class="panel-body">{body}</div>
        </div>
      panel

    /** Refresh the list of applications. */
    @client refresh() =
      apps = AdminController.App.list()
      panel = panel(apps)
      #inner_apps_panel <- panel

    /** Build the new app form. */
    @server_private build(state) =
      apps = @toplevel.App.list()
      list = panel(apps)
      <div id="apps_panel">
        <div id="inner_apps_panel">{list}</div>
        {Utils.panel_default(
          Utils.panel_heading(AppText.create()) <+>
          Utils.panel_body(
            Form.wrapper(
              Form.line({Form.Default.line with label=AppText.name(); id="new_app_name"; value=""}) <+>
              Form.line({Form.Default.line with label=AppText.link(); id="new_app_url"; value=""}) <+>
              <div class="form-group">{
                (WB.Button.make({button=<>{AppText.Create_app()}</> callback=create(_)}, [{primary}])
                 |> Xhtml.add_attribute_unsafe("data-complete-text", AppText.create(), _)
                 |> Xhtml.add_attribute_unsafe("data-loading-text", AppText.creating(), _)
                 |> Xhtml.add_id(some("create_app_button"), _))
              }</div>
            , false)
          ))}
      </div>

  }} // END APP


  /** {1} Bulk accounts. */

  Bulk = {{

    /** Create bulk accounts. */
    @client register(_evt) =
      list = Dom.get_value(#bulk_accounts)
      lines = String.explode("\n", list)
      (valid, errors) = List.foldi(i, line, (valid, errors) ->
        fields = List.map(String.trim, String.explode_with(";", line, false))
        match (fields) with
        | [first, last, user, pass, level | teams] ->
          level = Parser.int(level) ? 1
          ((first, last, user, pass, level, teams) +> valid, errors)
        | _ -> (valid, errors <+> <div class="alert alert-warning">{@i18n("Missing field at line {i}")}</div>)
      , lines, ([], <></>))
      do #bulk_parse_errors <- errors
      AdminController.register_list(valid,
        // Client side.
        | {success=errors} ->
          html = List.fold(error, html -> html <+> <>{error.message}</>, errors, <></>)
          #bulk_controller_errors <- html <+> <div class="alert alert-success">{AppText.Done()}</div>
        | {failure=_errors} -> void
      )

    @server_private
    build(state) =
      Utils.panel_default(
        Utils.panel_heading(@i18n("Bulk import")) <+>
        Utils.panel_body(
          <div id="bulk_parse_errors"></div>
          <div id="bulk_controller_errors"></div>
          <form role="form">
            <div class="form-group">
              <p class="form-control-static">{@i18n("The passwords are optional, and will be automatically generated if needed.")}</p>
              <label>{@i18n("First name; Last name; Username; Password; Level; [Team1; Team2; ...]")}</label>
              <textarea id=#bulk_accounts rows="10" cols="80" class="form-control">
              </textarea>
            </div>
            <div class="form-group">
              {WB.Button.make({button=<>{AppText.create()}</> callback=register}, [{primary}])
                |> Xhtml.add_attribute_unsafe("data-complete-text", AppText.create(), _)
                |> Xhtml.add_attribute_unsafe("data-loading-text", AppText.creating(), _)
                |> Xhtml.add_id(some("bulk_button"), _)
              }
            </div>
          </form>
      ))

  }} // END BULK

  /** {1} Indexing. */

  Indexing = {{

    progressbar =
      // Can't get this to work...
      //<div id=#reindex_progress class="progress progress-success progress-striped active"
      //     role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0">
      //  <div id=#reindex_progress_bar class="bar" style="width:0%;"></div>
      //</div>
      <div class="progress">
        <progress
            id="reindex_progress_bar" role="progressbar"
            class="progress-bar progress-bar-success active"
            max="100" value="0">
        </progress>
      </div>

    /** Update the progress bar. */
    @client progress(percent: int) =
      //Dom.set_style(Dom.select_raw_unsafe("#reindex_progress_bar"), [{width={percent=float_of_int(percent)}}])
      Dom.set_value(#reindex_progress_bar, "{percent}")

    /** Launch the reindexing of part of the index. */
    @client reindex(kind, btnid, _evt) =
      do Button.loading(#{btnid})
      do Dom.show(#reindex_progress_bar)
      Search.All.reindex(kind, progress, ->
        // Client side.
        do Button.reset(#{btnid})
        do Dom.hide(#reindex_progress_bar)
        Dom.set_value(#reindex_progress_bar, "0")
      )

    /** Clear a part of the index. */
    @client clear(kind, btnid, _evt) =
      do Button.loading(#{btnid})
      Search.All.clear(kind, ->
        // Client side.
        Button.reset(#{btnid})
      )

    /** Build an index form line. */
    actions(kind, title: string, name: string) =
      reindex =
        WB.Button.make({
          button= <><span class="fa fa-repeat-circle-o"></span> {@i18n("Reindex")}</>
          callback= reindex(kind, "reindex-{name}",_)
        }, [{default}]) |>
        Xhtml.add_attribute_unsafe("data-complete-text", @i18n("Reindex"), _) |>
        Xhtml.add_attribute_unsafe("data-loading-text", @i18n("Indexing..."), _) |>
        Xhtml.add_id(some("reindex-{name}"), _)
      clear =
        WB.Button.make({
          button= <><span class="fa fa-trash-o"></span> {@i18n("Delete index")}</>
          callback= clear(kind, "delete-{name}",_)
        }, [{default}]) |>
        Xhtml.add_attribute_unsafe("data-complete-text", @i18n("Delete index"), _) |>
        Xhtml.add_attribute_unsafe("data-loading-text", @i18n("Deleting index..."), _) |>
        Xhtml.add_id(some("delete-{name}"), _)
    // Actions line.
    <div class="form-group">
      <label class="label-fw">{title}</label>
      {reindex}{clear}
    </div>

    /** Build the indexing panel. */
    @server_private build(state) =
      Utils.panel_default(
        Utils.panel_heading(AppText.Indexing()) <+>
        Utils.panel_body(
          <form role="form">
            <div class="form-group">
              <p class="form-control-static text-info">{AppText.reindex_help()}</p>
              <p class="form-control-static">{AppText.reindex_help_small()}</p>
            </div>
            {actions({messages}, AppText.emails(), "messages")}
            {actions({files}, AppText.files(), "files")}
            {actions({users}, AppText.users(), "users")}
            {actions({contacts}, AppText.contacts(), "contacts")}
            <div class="form-group">{progressbar}</div>
          </form>
        ))

  }} // END INDEXING

  @server
  build(state: Login.state, mode: string, path: Path.t) =
    Content.check_admin(state,
      match (mode) with
      | "settings" -> Settings.build(state)
      | "classification" -> LabelView.build(state, true)
      | "indexing" -> Indexing.build(state)
      | "bulk" -> Bulk.build(state)
      | "apps" -> App.build(state)
      | _ -> Content.non_existent_resource
      end)


  /** Return the action associated with a mode. */
  @private action(mode: string) =
    match (mode) with
    | "classification" ->
      [{
        text= @i18n("New class")
        action= LabelView.create(true, _)
        id= SidebarView.action_id
      }]
    | _ -> []

  /** {1} Construction of the sidebar. */
  Sidebar: Sidebar.sign = {{

    build(state, options, mode) =
      view = options.view
      onclick(mode) = Content.update_callback({mode= {admin=mode} path= []}, _)

      if (Login.is_super_admin(state)) then
        List.flatten(
          [ action(mode),
            [
              { name="settings"  id="settings" icon="gear-o"          title = AppText.settings()      onclick = onclick("settings") },
              { name="classes"   id="classes"  icon="tags-o"          title = @i18n("Classes")        onclick = onclick("classification") },
              { name="indexing"  id="indexing" icon="repeat-circle-o" title = AppText.Indexing()      onclick = onclick("indexing") },
              { name="bulk"      id="bulk"     icon="users-o"         title = @i18n("Bulk accounts")  onclick = onclick("bulk") },
              { name="apps"      id="apps"     icon="cube"            title = AppText.Apps()          onclick = onclick("apps") }
            ]
          ]
        )
      else []

  }} // END SIDEBAR

}}
