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

// Global alias used in all views
WB = WBootstrap

module Keyboard {

  client function Dom.event_propagation propagation_handler(Dom.event e) {
    propagation = {stop_propagation : false, prevent_default : false};
    if (not(Dom.is_empty(Dom.select_raw_unsafe("input:focus, textarea:focus"))))
      propagation
    else
      match (e) {
      case { key_code : { some : 47 }, ... }:
        {propagation with prevent_default : true}
      case { key_code : { some : 114 }, key_modifiers : [], ... }:
        {propagation with prevent_default : true}
      default: propagation
      }
  }

  client function handler(Dom.event e) {
    if (not(Dom.is_empty(Dom.select_raw_unsafe("input:focus, textarea:focus"))))
      void
    else {
      match (e) {
      case { key_code : { some : 99 }, key_modifiers : [], ... }:
        ComposeView.new("", e)
      case { key_code : { some : 117 }, key_modifiers : [], ... }:
        UploadView.show(e)
      case { key_code : { some : 109 }, key_modifiers : [], ... }:
        MessageView.mark_read(e)
      // case { key_code : { some : 105 }, key_modifiers : [], ... }:
      //   Dom.trigger(#info_toggle, {click})
      case { key_code : { some : 47 }, ... }: SearchView.focus(e)
      // case { key_code : { some : 114 }, key_modifiers : [], ... }:
      //   Dom.trigger(#quick_reply, {click})
      case { key_code : { some : 115 }, key_modifiers : [], ... }:
        Dom.trigger(#star_message, {click})
      case { key_code : { some : 106 }, key_modifiers : [], ... }:
        MessageView.Snippet.next(e)
      case { key_code : { some : 107 }, key_modifiers : [], ... }:
        MessageView.Snippet.prev(e)
      default: void
      }
    }
  }

}

client logout_timer_time = ClientReference.create(60)
client logout_timer_ctxt = ClientReference.create(option(ThreadContext.client) {none})

module Content {

    log = Log.notice("Content", _)
    error = Log.error("Content", _)

    // // FIXME: move to automated JS
    // function choose_selected_box(anchor) {
    //     function act(anchor) {
    //         Dom.remove_class(Dom.select_raw_unsafe("li"), "selected");
    //         Dom.add_class(Dom.select_class(anchor), "selected");
    //         void
    //     }
    //     update({messages: {inbox}}, anchor)
    // }

    // client function update_items(anchor) {
    //     Content.choose_selected_box(anchor);
    //     void
    // }

    function insert_loading() {
        Log.info("Loading", "content...");
        if (Dom.is_empty(#loading-content)) {
          loading =
            <div id="loading-content" class="loading-content" >
              <img src="/resources/img/loader.gif" alt="{@i18n("Loading...")}"/>
            </div>;
          #content = loading
        } else void
    }

    function make_alert(string title, xhtml description) {
      WBootstrap.Alert.make({
        block: ~{ title, description },
        actions: none,
        closable: false
      }, {error})
    }

    login_please =
      make_alert(
        @i18n("Your session has expired!"),
        <>{@i18n("Please log in to access this resource")}</>
      )

    non_existent_resource =
      make_alert(
        @i18n("Oops!"),
        <>{@i18n("Looks like the resource you are looking for does not exist ...")}</>
      )

    not_allowed_message =
      make_alert(
        @i18n("Sorry!"),
        XmlConvert.of_alpha(AppText.not_allowed_message())
      )

    not_allowed_resource =
      make_alert(
        "Sorry!",
        XmlConvert.of_alpha(AppText.not_allowed_resource())
      )

    exposed function logout_and_reload(ctx) {
      state = Login.get_state()
      log("logout_and_reload: unlogging {state}")
      key = state.key
      error("INACTIVE LOGOUT {key}")
      Login.logout()
      ClientEvent.remove_inactivity_delay(ctx)
      Client.do_reload(false)
    }

    client function do_confirm(ctx, btn_id, confirmed, _) {
      Button.reset(#{btn_id})
      Modal.hide(#modal_logout_confirm)
      stop_logout_timer()
      if (confirmed) {
        logout_and_reload(ctx)
      }
    }

    recursive private client function logout_timer_function() {
      time = ClientReference.get(logout_timer_time)
      if (time > 0) {
        time = time - 1
        ClientReference.set(logout_timer_time, time)
        #logout_confirm_time = AppText.logout_timer(time)
      } else {
        logout_timer.stop()
        match (ClientReference.get(logout_timer_ctxt)) {
        case {some:ctx}: logout_and_reload({some:ctx});
        case {none}: void;
        }
      }
    }

    recursive private client logout_timer = Scheduler.make_timer(1000, logout_timer_function)

    client function start_logout_timer(ctx) {
      ClientReference.set(logout_timer_time, AdminController.get_grace_period())
      ClientReference.set(logout_timer_ctxt, ctx)
      logout_timer.start()
    }

    client function stop_logout_timer() {
      ClientReference.set(logout_timer_ctxt, {none})
      logout_timer.stop()
    }

    function logout_confirm(ctx) {
      Modal.make(
       "modal_logout_confirm",
       <>{AppText.session_expired()}</>,
       <><div>{AppText.logout_confirm()}</div>
         <div id="logout_confirm_time">{AppText.logout_timer(AdminController.get_grace_period())}</div>
       </>,
       (WBootstrap.Button.make({button:<><i class="fa fa-check"></i> {AppText.yes()}</>,
                        callback:do_confirm(ctx, "confirm_yes", true, _)}, [{success}])
        |> Xhtml.add_id(some("confirm_yes"), _)) <+>
       (WBootstrap.Button.make({button:<><i class="fa fa-times"></i> {AppText.no()}</>,
                        callback:do_confirm(ctx, "confirm_no", false, _)}, [{primary}])
        |> Xhtml.add_id(some("confirm_no"), _)),
       {Modal.default_options with backdrop : false, static : false, keyboard : false})
    }

    // FIXME: not here
    exposed function init_server(channel) {
      state = Login.get_state()
      key = state.key
      if (not(Login.is_logged(state))) void
      else {
        ctx = ThreadContext.Client.get_opt({current})
        timeout = Duration.min(AdminController.get_timeout())
        _ = ClientEvent.set_inactivity_delay(ctx, timeout)
        clek =
            ClientEvent.set_on_inactive_client(function(ctx) {
              start_logout_timer({some:ctx})
              Modal.show(#modal_logout_confirm)
            })
        Dom.bind_beforeunload_confirmation(function(_) {
          Notification.unregister(key, channel)
          ClientEvent.remove_event(clek)
          ClientEvent.remove_inactivity_delay(ctx)
          none
        })
        Notification.register(key, channel)
        // Update profile picture.
        match (Option.bind(RawFile.get_thumbnail, User.get_picture(state.key))) {
          case {some: picture}:
            #profile_picture = <img src={Utils.dataUrl(picture)} class="user-img"/>
          default: void
        }
      }
    }

    xhtml drop_file =
        <>
         <img id="compose_file_loader" src="/resources/img/loader.gif" style={
         [Css_build.display({css_none})]}/>
         {@i18n("Drop files here")}
        </>

    // client function clear_modal_errors() {
    //   Dom.remove_class(Dom.select_raw_unsafe("#modal_compose .form-group"), "error")
    // }

    client function clear_tooltips() {
      Dom.remove(Dom.select_class("tooltip"))
    }


    exposed function do_setup_admin(pass) {
      // Build admin user.
      if (Admin.undefined()) {
        Admin.create(pass)
        Login.login("admin", pass)
      }
    }
    client function setup_admin(_evt) {
      pass = Dom.get_value(#pass) |> String.trim
      passrepeat = Dom.get_value(#passrepeat) |> String.trim

      if (pass != passrepeat || pass == "") Notifications.error("Error", <>{@i18n("Invalid password")}</>)
      else do_setup_admin(pass)
    }

    protected function signin(state) {
      <>
      <h3>{AppText.sign_in_to_mailbox()}</h3>
      <div id="login">
        {Login.build(state)}
      </div>
      { if (not(Admin.only_admin_can_register())) {
          <a onclick={function(_){ #signin_well = signup(state) }}>
            {@i18n("Don't have an account? Sign up")}
          </a>
        }
        else <></>
      }
      </>
    }

    protected function signup(state) {
      AdminView.register(state, none) <+>
      <a onclick={function(_){ #signin_well = signin(state) }}>
        {@i18n("Already have an account? Sign in")}
      </a>
    }

    /** Log in window, if user is not connected. */
    @expand protected function loginbox(state) {
      <div class="home-card">
        <div class="container">
          <div class="app-icon"></div>
          <h1>{Admin.logo()}</h1>
          <div class="well">
            <div id="signin_well">
              {signin(state)}
            </div>
          </div>
        </div>
      </div>
    }


    @expand protected function passwordbox(state) {
      <div class="home-card">
        <div class="container">
          <div class="app-icon"></div>
          <h1>{Admin.logo()}</h1>
          <div class="well">
            <h3>{@i18n("Setup your PEPS in two steps")}</h3>
            <form role="form" class="form-simple">
              <div class="form-group">
                <label class="control-label" for="domain">{@i18n("Admin Password")}</label>
                <input id="pass" type="password" class="form-control" placeholder="{@i18n("Password")}"/>
              </div>
              <div class="form-group">
                <label class="control-label" for="domain">{@i18n("Repeat")}</label>
                <input id="passrepeat" type="password" class="form-control" placeholder="{@i18n("Password repeat")}"/>
              </div>
              <div class="form-group">
                <button type="button" class="btn btn-block btn-primary" onclick={setup_admin}>{@i18n("Next")}</button>
              </div>
            </form>
          </div>
        </div>
      </div>
    }

    /**
     * Function called when the main page is ready.
     * URN is some if the user is logged in, else none.
     */
    client function init_client(option(URN.t) urn, _) {
      Dom.bind_with_options(
        Dom.select_document(),
        {keypress}, Keyboard.handler,
        [ {propagation_handler : Keyboard.propagation_handler} ]
      ) |> ignore
      Collapse.init(Dom.select_class("collapse"))
      Dropdown.init(Dom.select_class("dropdown-toggle"))

      channel = Session.make_callback(Notifications.handler)
      init_server(channel)
      // TODO: preserve last mode and path?
      log("init_client: {urn}")
      Option.iter(update(_, true), urn)
    }

    protected function build(Login.state state, URN.t urn) {
      unprotected = Mode.unprotected(urn.mode) // Give access to unprotected share links.
      logged = Login.is_logged(state)

      (view, _, _, _) = SettingsController.get_user_preferences(state.key)
      cl = if (view == {folders}) " narrow" else ""
      init = if (logged || unprotected) init_client(some(urn), _) else init_client(none, _)
      modals =
        if (Mode.is_share(urn.mode))
          <></>
        else
          logout_confirm(ThreadContext.Client.get_opt({current})) <+>
          FolderView.build_form(state, none) <+>
          SearchView.build_form(state)

      <div id="main" onready={init} class="main o-selectable{cl}">
        <div class="notification_area o-selectable" id="notification_area"/>{
        if (Admin.undefined() && not(unprotected))
          passwordbox(state)
        else if (not(logged || unprotected))
          loginbox(state)
        // Condition shown iff active licensing.
        else
          <div id="appsidebar" class="pull-right" style="width:320px; display:none;"></div> <+>
          <div id="content" class="content"></div> <+>
          modals
      }</div>

    }

  protected function selector(state, URN.t urn) {
    match (urn.mode) {
      case {messages: box}:   MessageView.build_box(state, box, urn.path, none)
      case {files: mode}:     FileView.build(state, mode, urn.path)
      case {people: mode}:    PeopleView.build(state, mode, urn.path)
      case {admin: mode}:     AdminView.build(state, mode, urn.path)
      // TODO for Norman
      case ~{app, active: _}: AppView.build(state, app, urn.path)
      case {share: link}:     FileView.build_shared(link, urn.path)
      case {settings: mode}:  SettingsView.build(state, mode, urn.path)
      case {dashboard: mode}: Dashboard.build(state, mode, urn.path)
      case {error}:           non_existent_resource
    }
  }

  // function to verify view requirements
  // should be called by every view main function to ensure consistency
  function ensure(req, state, resource) {
    if ((req=={logged} || req=={admin} || req=={super}) && not(Login.is_logged(state))) { login_please }
    else if ((req=={admin} || req=={super}) && not(Login.is_admin(state))) { not_allowed_resource }
    else if (req=={super} && not(Login.is_super_admin(state))) { not_allowed_resource }
    else { resource }
  }

  /** check_admin state */
  check_admin = ensure({admin}, _, _)
  check_super = ensure({super}, _, _)

  function onboarding(state) {
    if (SettingsController.onboarding(state.key)) {
      match (OnboardView.build(state)) {
        case {some: html}:
          Notifications.warning("Welcome to PEPS", html)
          Dom.add_class(#notification_area, "notify-static")
        default:
          Dom.remove_class(#notification_area, "notify-static")
      }
    } else {
      Dom.remove_class(#notification_area, "notify-static")
    }
  }

  /**
   * Update the client state.
   * Grouping the updates like this help reducing the number of client calls, and optimes the
   * slicing delay.
   */
  client function upload(urn, content, sidebar, badges) {
    // Clear current notifications.
    URN.change(urn)
    TopbarView.activate(urn.mode)
    Notifications.clear()
    Content.clear_tooltips()
    // Updates contents.
    #content = content
    #sidebar = sidebar
    // Insert badges.
    Notifications.Badge.insert(badges)
  }

  @async
  function change_urn(state, URN.t urn, force) {
    current = URN.get()
    if (current == urn && not(force))
      // Add reloading calls to subviews.
      void
    else {
      // Always reload the content.
      content = Content.selector(state, urn)
      sidebar = SidebarView.content(state, urn.mode)
      badges = Notifications.Badge.fetch(urn.mode)
      upload(urn, content, sidebar, badges)
      // onboarding(state)
    }
  }

  function update_callback(URN.t urn, _) {
    update(urn, false)
  }

  @async
  exposed function update(URN.t urn, bool force) {
    // Get a new state. CHECK
    state = Login.get_state()
    change_urn(state, urn, force)
  }

  /** Return to the main view. */
  function reset() {
    update(URN.init, true)
  }

  /** Refresh the view. */
  function refresh() {
    update(URN.get(), true)
  }

  /** Toggle an app sidebar. */
  client function toggleSidebar(Mode.t mode, _evt) {
    name = Mode.class(mode)
    if (Dom.has_class(#{name}, "active")) hideSidebar(mode)
    else showSidebar(mode)
  }

  /** Display an app sidebar. */
  client function showSidebar(Mode.t mode) {
    name = Mode.class(mode)
    Dom.show(#appsidebar)
    // Close open sidebars.
    Dom.iter(function (sidebar) {
      Parser.parse(parser {
        case "sidebar_" id=Rule.ident:
          if (id != name) { // Spare the mode to load.
            Dom.remove_class(#{id}, "active") // Toggle the topbar icon.
            Dom.hide(sidebar) // Hide the sidebar (do not destroy it: keep the state).
          }
        case .*: void
      }, Dom.get_id(sidebar))
    }, Dom.select_class("app-sidebar"))
    // Look up mode sidebar.
    sidebar = #{"sidebar_{name}"}
    if (Dom.is_empty(sidebar)) #appsidebar += buildSidebar(mode) // Load the sidebar.
    else Dom.show(sidebar) // Toggle the existing sidebar.
    // Activate topbar icon.
    Dom.add_class(#{name}, "active")
  }

  /** Hide an app's sidebar. */
  client function hideSidebar(Mode.t mode) {
    name = Mode.class(mode)
    Dom.iter(Dom.hide, #{"sidebar_{name}"})
    Dom.hide(#appsidebar)
    Dom.remove_class(#{name}, "active")
  }

  /** Build a sidebar. */
  exposed function buildSidebar(Mode.t mode) {
    state = Login.get_state()
    name = Mode.class(mode)
    if (not(Login.is_logged(state))) login_please
    else
      <div class="app-sidebar" id="sidebar_{name}" style="width: 320px;">
        {selector(state, URN.make(mode, []))}
      </div>
  }

}
