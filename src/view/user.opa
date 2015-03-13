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

/** Storage of the decoded secret key. */
private client reference(option(uint8array)) secretKey = ClientReference.create(none)

module UserView {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[UserView]", msg) }
  private function debug(msg) { Log.notice("[UserView]", msg) }

  /** {1} View components. */

  /** Create a div containing a user img that will load after the page is ready. */
  protected function userimg(option(RawFile.id) raw, onclick) {
    match (raw) {
      case {some: raw}: <img src="/thumbnail/{raw}" class="user-img" onclick={onclick}/>
      default: <div class="user-img user-img-default" onclick={onclick}></div>
    }
  }

  client function dummyhandler(_evt) { void }

  /**
   * @param display: show the checkbox.
   * @param checked: condition to tick the checkbox if shown.
   */
  function checkbox(text, id, display, checked) {
    if (display)
      <label class="checkbox-inline">
        { if (checked) <input type="checkbox" id="{id}" checked="checked"/>
          else <input type="checkbox" id="{id}"/> } {text}
      </label>
    else
      <></>
  }

  /** Secret key management. */
  module SecretKey {

    /**
     * Decode the user secret key and set the client reference.
     * The function returns true iff the secret key was successfully decrypted.
     */
    private client function set(User.key user, string password) {
      data = User.encryption(user)
      match (data) {
        case {some: ~{nonce, salt, secretKey}}:
          pass = Uint8Array.decodeUTF8(password)
          salt = Uint8Array.decodeBase64(salt)
          nonce = Uint8Array.decodeBase64(nonce)
          secretKey = Uint8Array.decodeBase64(secretKey)
          // Compute the master key.
          masterKey = TweetNacl.pbkdf2(pass, salt, 5000, TweetNacl.SecretBox.keyLength)
          // Decrypt the secret key.
          secretKey = TweetNacl.SecretBox.open(secretKey, nonce, masterKey)
          ClientReference.set(@toplevel.secretKey, secretKey)
          secretKey
        default: none
      }
    }

    /** Return the secret key. */
    client function get() { ClientReference.get(secretKey) }

    /** Same as {get}, but prompt the user for its password if the key hasn't been obtained yet. */
    client function prompt(User.key user, string msg, callback) {
      match (get()) {
        case {some: secretKey}: callback(some(secretKey))
        default: passwordInput(user, msg, callback)
      }
    }

    /** Password input modal. */
    private client function passwordInput(User.key user, msg, callback) {
      // Set the password before calling the callback.
      function doconfirm(_evt) {
        password = Dom.get_value(#passwordinput)
        match (set(user, password)) {
          case {some: secretKey}:
            // Destroy the modal and return with the secretKey.
            Dom.remove(#passwordmodal)
            callback(some(secretKey))
          default:
            Notifications.notify("passwordnotify", AppText.password(), <>{@i18n("Invalid password")}</>, {error})
            Dom.clear_value(#passwordinput)
        }
      }
      // Destroy the modal and return with no value.
      function docancel(_evt) {
        Dom.remove(#passwordmodal)
        callback(none)
      }

      prompt =
        <>
        <div id="passwordnotify"/>
        {Form.wrapper(
          Form.form_group(
            <div class="form-control-static">{msg}</div>
            <input type=password id="passwordinput" placeholder="{AppText.password()}" class="form-control"></input>
            )
        , true)}
        </>
      ok = WB.Button.make({button: <>{AppText.Ok()}</>, callback: doconfirm}, [{primary}])
      cancel = WB.Button.make({button: <>{AppText.Cancel()}</>, callback: docancel}, [{`default`}])
      modal =
        Modal.make("passwordmodal", <>{@i18n("Authentication")}</>,
          prompt, <>{cancel}{ok}</>,
          {Modal.default_options with backdrop: false, static: false, keyboard: false}
        )
      #main =+ modal // APPEND the modal so it appears in front of other modals.
      Modal.show(#passwordmodal)
      Scheduler.sleep(500, function () { Dom.give_focus(#passwordinput) })
      Dom.bind(#passwordmodal, {custom: "hidden.bs.modal"}, docancel) |> ignore
      Dom.bind_with_options(#passwordinput, {newline}, doconfirm, [{stop_propagation}, {prevent_default}]) |> ignore
    }


  } // END SECRETKEY

  /** {1} User list refresh. ***/

  /**
   * Refresh a single user in the list.
   * Instead of reloading all the page, a single element is updated.
   * @param key key of the updated user
   * @param update the kind of update: {new}, {delete}, {update}
   */
  exposed @async function void refresh(User.key key, Journal.Common.event event) {
    state = Login.get_state()
    if (Login.is_logged(state))
      match (event) {
        case {update}:
          match (User.get(key)) {
            case {some: user}:
              sgn = User.get_signature(state.key)
              div = User.highlight(user, none, none, none) |> build_item(sgn, _)
              view = build_user(state, user)
              #user_viewer = view
              #{key} = div
            default: void
          }
        // The parent is the list element.
        case {delete}:
          Dom.select_parent_one(#{key}) |> Dom.remove
          #user_viewer = <></>
        // Reload the full list, for want of a better insertion system.
        case {new}:
          match (User.get(key)) {
            case {some: user}:
              view = build_user(state, user)
              #user_viewer = view
              load_page(User.emptyFilter)
            default: void
          }
      }
  }

  /** {1} Callbacks. */

  client saveCallback = function {
    case {success: key}:
      Button.reset(#save_user_button)
      refresh(key, {update})
      Notifications.info(AppText.Update(), <>{@i18n("User updated")}</>)
    case ~{failure}:
      Button.reset(#save_user_button)
      Notifications.error(AppText.Update(), <>{failure.message}</>)
  }

  /** Push user changes to the server. */
  client function save(User.key key, string username, _evt) {
    Button.loading(#save_user_button)
    level = Dom.get_value(#user_level) |> Parser.int
    level = level ? 1
    // FIXME: offer the possibility to change the name.
    admin = Dom.is_checked(#user_is_admin)
    super = Dom.is_checked(#user_is_super_admin)
    status =
      if (super) {super_admin:void}
      else if (admin) {admin:void}
      else {lambda:void}
    // Send server request.
    UserController.Async.save(key, level, status, saveCallback)
  }

  /** Change blokc status of a user. */
  client function changeBlock(User.key key, string username, bool block, _evt) {
    Button.loading(#block_button)
    UserController.Async.block(key, block, function {
      // Client side.
      case {success}:
        Button.reset(#block_button)
        load_user(some(key))
        message =
          if (block) @i18n("User {username} has been blocked")
          else @i18n("User {username} has been unblocked")
        Notifications.info(AppText.Block(), <>{message}</>)
      case ~{failure}:
        Button.reset(#block_button)
        Notifications.error(AppText.Block(), <>{failure.message}</>)
    })
  }

  /** Reset the user password. */
  client function reset(User.key key, string username, _evt) {
    if (Client.confirm(@i18n("Are you sure you want to reset this user password?")))
      UserController.Async.reset(key, function {
        // Client side.
        case {success: newpass}: Notifications.info(@i18n("New Password for {username}"), <>{newpass}</>)
        case ~{failure}: Notifications.error(AppText.reset(), <>{failure.message}</>)
      })
  }

  /** Delete a user from the list. */
  client function delete(User.key key, string username, _evt) {
    if (Client.confirm(@i18n("Are you sure you want to delete this user?")))
      UserController.Async.delete(key, function {
        // Client side.
        case {success}:
          refresh(key, {delete})
          Notifications.info(@i18n("Deleted user {username}"), <>{AppText.Ok()}</>)
        case ~{failure}: Notifications.error(@i18n("Delete user {username}"), <>{failure.message}</>)
      })
  }

  /** Remove the user from a team. Triggered by clicking on the X button on team labels. */
  client function removeTeam(User.t user, Team.t team, string id, Dom.event _evt) {
    if (List.mem(team.key, user.teams)
      && Client.confirm(@i18n("Remove user {user.username} from team '{team.name}'?")))
      UserController.Async.update_teams(user.key, {removed_teams: [team.key], added_teams:[]}, function {
        case {success: teams}: saveCallback({success: user.key})
        case ~{failure}: saveCallback(~{failure})
      })
  }

  /** Add a team to the list of user teams. */
  client function addTeam(User.key key, User.t user, Dom.event _evt) {
    function action(team) {
      // Client side.
      if (not(List.mem(team, user.teams)))
        UserController.Async.update_teams(user.key, {added_teams: [team], removed_teams:[]}, function {
          case {success: teams}: saveCallback({success: user.key})
          case ~{failure}: saveCallback(~{failure})
        })
    }
    TeamChooser.create(~{
      title: @i18n("Add team to {user.username}"),
      action, excluded: user.teams, user: none
    })
  }

  exposed function get_user_teams(user) {
    state = Login.get_state()
    teams = User.get_admin_teams(user.key)
    function remove(team) { some(removeTeam(user, team, _, _)) }
    TeamView.layout(teams, remove, [])
  }

  /** {1} Single user display.
   *
   * Select a message and display it in the #user_viewer.
   * User loading is asynchronous.
   */

  /** Fetch the user information and build the html display. */
  exposed @async function server_user(User.key key) {
    UserController.Async.open(key, function {
      case ~{failure}: finish_user({failure: failure.message})
      case {success: user}:
        // Server side.
        state = Login.get_state()
        t0 = Date.now()
        html = build_user(state, user) |> Xhtml.precompile // Precompile for faster transfer and insertion.


        // Notification.Broadcast.badges(state.key)
        finish_user({success: (user.key, html)})
    })
  }

  /** Insert the loaded user in the user display. */
  client function finish_user(res) {
    Notifications.clear_loading()
    match (res) {
      case {success: (key, html)}:
        #user_viewer = html
        URN.change(URN.make({people: "users"}, [key]))
        // choose_active_message(mid)
      case {failure: msg} ->
        #user_viewer = Content.not_allowed_resource
    }
  }

  /**
   * If the user key is defined (the urn path gives a user key), send a request for the user information.
   * The user is loaded by the callback, {finish_user}.
   */
  client function load_user(key) {
    match (key) {
      case {some: key}: server_user(key)
      default: #user_viewer = <></>
    }
  }

  /** Build the user edition form. */
  protected function build_user(state, user) {
    blocked = user.blocked
    blockText = if (blocked) AppText.Unblock() else AppText.Block()
    blockAction = changeBlock(user.key, user.username, not(blocked), _)

    teams = get_user_teams(user)
    my_status = User.get_status(state.key)
    email = user.email
    picture = userimg(user.picture, dummyhandler)

    // Credentials selection.
    admin = checkbox(AppText.Admin(), "user_is_admin",
      my_status == {super_admin} || my_status == {admin},
      user.status == {admin} || user.status == {super_admin}
    )
    super = checkbox(AppText.Super_Admin(), "user_is_super_admin",
      my_status == {super_admin},
      user.status == {super_admin}
    )
    actions =
      <div class="pull-right btn-group">
        <a id="block_button" class="btn btn-sm btn-default" onclick={blockAction}
            data-loading-text="{AppText.Blocking()}">
          <i class="fa fa-lock-o"/> {blockText}</a>
        <a id="reset_button" class="btn btn-sm btn-default" onclick={reset(user.key, user.username, _)}>
          <i class="fa fa-refresh"/> {@i18n("Reset password")}</a>
        <a id="delete_button" class="btn btn-sm btn-default" onclick={delete(user.key, user.username, _)}
            data-loading-text="{AppText.Deleting()}" data-complete-text="{AppText.delete()}">
          <i class="fa fa-trash-o"/> {AppText.delete()}</a>
      </div>
    level =
      Form.line({ Form.Default.line with
        label: @i18n("Clearance Level"), id: "user_level",
        typ: "number", value: "{user.level}"
      })
    save =
      WB.Button.make({
        button: <>{@i18n("Save changes")}</>,
        callback: save(user.key, user.username, _)
      }, [{primary}]) |>
      Xhtml.add_attribute_unsafe("data-complete-text", @i18n("Save changes"), _) |>
      Xhtml.add_attribute_unsafe("data-loading-text", AppText.saving(), _) |>
      Xhtml.add_id(some("save_user_button"), _)
    form =
      Form.wrapper(
        <><div class="pane-heading">
          {actions}
          {picture}
          <h3>{Email.to_name(email)}</h3>
        </div>
        <div class="form-group">
          <label class="control-label">{AppText.email()}</label>
          <p class="form-control-static">{Email.to_string_only_address(email)}</p>
        </div>
        {level}
        <div class="form-group" id="user_teams">
          <label class="control-label">{AppText.teams()}</label>
          <a onclick={addTeam(state.key, user, _)} class="fa fa-plus-circle-o"/>
          <div>{teams}</div>
        </div>
        <div class="form-group">
          {super}{admin}
        </div>
        <div class="form-group">{save}</div></>
      , false)
    // Main structure.
    <div class="user">
      {form}
    </div>
  }

  /** Build the user registration form. */
  exposed function build_register(_) {
    state = Login.get_state()
    #user_viewer = AdminView.register(state, {some: function (user) { refresh(user.key, {new}) }})
  }


  /**
   * {1} User list.
   *
   * The list display is an infinite scroll, initialized with a set of users, while more users are loaded
   * as the user scrolls towards the end of the list.
   */


  /** Build the user panel, filled with the first users. */
  exposed @async function server_page(filter, callback) {
    state = Login.get_state()
    if (not(Login.is_admin(state)))
      callback(Xhtml.precompile(<>{AppText.login_please()}</>))
    else {
      t0 = Date.now()
      first = {fname: "", lname: ""}
      page = UserController.fetch(state, first, filter, [])


      build_page(state, page, none, filter) |> Xhtml.precompile |> callback
    }
  }

  /**
   * Initialize the user list by inserting the list header.
   * This function is called once to build the page layout.
   */
  client function finish_panel(html) { #users_list = html }
  client function load_page(filter) { server_page(filter, finish_panel) }

  /**
   * Fetched pre-formatted users from the database, ready for
   * insertion in the view. The asynchronous status ensures that the list scroll remains fluid.
   */
  exposed @async function server_users(User.fullname ref, filter, callback) {
    state = Login.get_state()
    if (not(Login.is_admin(state)))
      callback(Xhtml.precompile(<>{AppText.login_please()}</>), ref, 0)
    else {
      t0 = Date.now()
      page = UserController.fetch(state, ref, filter, [])
      signature = User.get_signature(state.key)


      pagehtml = build_items(signature, page) |> Xhtml.precompile
      callback(pagehtml, page.last, page.size)
    }
  }

  /**
   * Insert the loaded elements into the view.
   * If more users are to be expected, then restore the {scroll} handler, with updated
   * parameters (set to fetch the following users).
   */
  client function void finish_load(filter, html, ref, size) {
    #users_list_items += html                     // Append new messages to the end of the list.
    if (size > 0)
      Dom.bind(#users_list_items, {scroll}, scroll(ref, filter, _)) |> ignore
  }

  /**
   * Load more messages, and append them to the end of the list.
   * Called exclusively by the function {message_scroll}, which detects the optimal moment for loading more messages.
   * This function must NOT be async: we need to deactivate the {message_scroll} event handler, to avoid duplicate
   * calls to {server_messages}. {server_messages} IS asynchronous, and this ensures the fluidity of the scroll.
   */
  client function void load_more(User.fullname ref, filter) {
    debug("load_more: from:{ref}")
    Dom.unbind_event(#users_list_items, {scroll})              // Unbind event to avoid multiple requests.
    server_users(ref, filter, finish_load(filter, _, _, _))    // Send request for more elements.
  }

  /**
   * Called on scroll events. Detect when less than a certain amount of users remain in the list
   * to know when to trigger the function to fetch more messages.
   * User height is estimated at 80px ofr the purpose of determining the number of messages left in the list.
   * When less than three times the amount of visible users remain in the list, new users are fetched.
   * Same as {load_more}, this function needn't be asynchronous.
   */
  client function void scroll(ref, filter, _evt) {
    full = Dom.get_scrollable_size(#users_list_items).y_px
    current = Dom.get_scroll_top(#users_list_items)
    height = Dom.get_height(#users_list_items)
    mvisible = height/80
    mleft = (full-current)/80 - mvisible  // Number of users left in the list to scroll for.
    if (mleft < 3*mvisible) load_more(ref, filter)
  }

  /**
   * Build a user list element.
   * @param user a user short profile.
   * @param signature the active user's signature, used to create the {write_to} item actions.
   */
  protected function build_item(signature, user) {
    key = user.key
    email =
      match ((user.highlighted.fname, user.highlighted.lname)) {
        case ({some: fname}, {some: lname}):
          fname = Xhtml.of_string_unsafe(fname)
          lname = Xhtml.of_string_unsafe(lname)
          <>{fname} {lname}</>
        case ({none}, {some: lname}):
          sp = if (user.first_name == "") "" else " "
          lname = Xhtml.of_string_unsafe(lname)
          <>{user.first_name}{sp}{lname}</>
        case ({some: fname}, {none}):
          sp = if (user.last_name == "") "" else " "
          fname = Xhtml.of_string_unsafe(fname)
          <>{fname}{sp}{user.last_name}</>
        default:
          <>{Email.to_name(user.email)}</>
      }
    badge =
      match (user.status) {
        case {lambda}: "badge"
        case {admin}: "badge admin"
        case {super_admin}: "badge superadmin"
      }
    level = AppConfig.level_view(user.level)
    teams = List.map(Team.get_name, user.teams) |> Misc.spanlist("teams", _)
    onclick = ComposeView.write_to({internal: {email: user.email, key: user.key, team: false}}, signature, _)
    load = function (_) { load_user(some(key)) }

    userimg(user.picture, onclick) <+>
    <div class="user" onclick={load}>
      {email}
      {teams}
    </div>
    <div class="{badge}">{level}</div>
  }

  /** Build a list of user items. */
  protected function build_items(signature, page) {
    t0 = Date.now()
    list = List.rev_map(function (user) {
      <a class="list-group-item" id="{user.key}">
        {build_item(signature, user)}
      </a>
    }, page.elts)


    List.fold(`<+>`, list, <></>)
  }

  /** Build the full panel containg the list of users. */
  protected function build_page(Login.state state, User.page page, query, filter) {
    // Empty list.
    if (page.size <= 0)
      <div class="pane-heading">
        <h3>{AppText.users()}</h3>
      </div>
      <div class="empty-text">
        <p>{AppText.no_users()}</p>
      </div>

    else {
      signature = User.get_signature(state.key)
      elts = build_items(signature, page)
      match (query) {
        // Query results.
        case {some: query}:
          user = List.head(page.elts).key // List is not empty.
          header =
            <div class="pane-heading" onready={function (_) { load_user(some(user)) }}>
              <h3>
                {AppText.search()} : {page.size} {@i18n("results for")} <small class="page_num">{query}</small>
              </h3>
            </div>
          header <+> <ul class="list-group">{elts}</ul>
        // Normal fetch.
        default:
          t0 = Date.now()
          ref = page.last
          teams = User.get_administrated_teams(state.key)
          usercount = User.count(teams)
          header =
            <div class="pane-heading">
              <h3>
                {AppText.users()} <small class="page_num">{@i18n("about {usercount} results")}</small>
              </h3>
            </div>
          html = header <+> <ul id="users_list_items" class="list-group" onscroll={scroll(ref, filter, _)}>{elts}</ul>


          html
      }
    }
  }

  protected function build(Login.state state, Path.t path) {
    Content.check_admin(state, {
      user = match (path) { case [key | _]: some(key); default: none }
      <div id=#users_list class="users_list pane-left" onready={function (_) { load_page(User.emptyFilter) }}></div>
      <div id=#user_viewer class="pane-right" onready={function (_) { load_user(user) }}></div>
    })
  }

}
