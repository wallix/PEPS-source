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

/** Options. */
type ContactView.options = {
  (Contact.t -> Contact.t) format, // Format the contact before saving to database.
  bool reset, // Display reset button.
  bool cancel, // Display cancel button.
  bool actions // Display standard actions bar: edit, block, delete.
}

module ContactView {

  /** {1} Utils. */

  private function log(msg) { Log.notice("ContactView:", msg) }

  /** The default options correspond to that of the standard contact edition. */
  ContactView.options defaults = {
    format: identity,
    reset: false,
    cancel: true,
    actions: true
  }

  /**
   * {1} Callbacks.
   * {2} Refresh.
   *
   * Refresh applies to contact view only. if the displayed list was of team users,
   * this is not going to have the expected result.
   */

  @async
  client refresh_callback = function {
    case {success: html}: Dom.transform([#contacts_list = html])
    case {failure: e}: void
  }
  @async
  exposed function refresh_contacts() {
    match (ContactController.get()) {
      case {success: contacts}:
        html = build_contacts(List.map(Contact.to_client_contact,contacts), false)
        refresh_callback({success: html})
      case ~{failure}:
        refresh_callback(~{failure})
    }
  }

  /** {2} Creation and modification. */

  @async
  client function save_callback(res) {
    Button.reset(#save_contact_button)
    match (res) {
      case {success: contact}:
        refresh_contacts()
        open_contact(contact.id, false, false, false)
        Notifications.info(AppText.Update(), <>{@i18n("Contact updated")}</>)
      case {failure: s}:
        Notifications.error(AppText.Update(), <>{s}</>)
    }
  }
  client function do_save(contact, format, _) {
    Button.loading(#save_contact_button)
    name = Dom.get_value(#contact_name)
    emails = extract("email-group", Parser.try_parse(Email.address_parser, _))
    phones = extract("phone-group", some)
    addresses = extract("address-group",
      function (formatted) { some({Contact.empty_contact_address with ~formatted}) })
    companies = extract("company-group",
      function (name) { some({Contact.empty_contact_organization with ~name}) })
    match ((emails.errors, phones.errors, addresses.errors, companies.errors)) {
      // Do NOT refresh the view; display a notification.
      case ([_], _, _, _): Notifications.error(AppText.contacts(), <>{@i18n("Malformed email addresses {String.concat(", ", emails.errors)}")}</>)
      case (_, [_], _, _): Notifications.error(AppText.contacts(), <>{@i18n("Malformed phone numbers {String.concat(", ", phones.errors)}")}</>)
      case (_, _, [_], _): Notifications.error(AppText.contacts(), <>{@i18n("Malformed addresses {String.concat(", ", addresses.errors)}")}</>)
      case (_, _, _, [_]): Notifications.error(AppText.contacts(), <>{@i18n("Malformed companies {String.concat(", ", companies.errors)}")}</>)
      default:
        ContactController.save(contact, format({
          contact with
          info.displayName: name,
          info.emails: emails.items,
          info.phoneNumbers: phones.items,
          info.addresses: addresses.items,
          info.organizations: companies.items
        }), save_callback)
    }
  }

  /** Create a new contact. */
  client function create(_evt) {
    html = contact_editor(Contact.empty_contact, <></>, {defaults with actions: false})
    open_callback({success: html}, true)
  }

  /** {2} Block and unblock. */

  @async
  client function block_contact_callback(res) {
    Button.reset(#block_contact_button)
    match (res) {
      case {success: (contact, b)}:
        refresh_contacts()
        open_contact(contact.id, false, false, false)
        Notifications.info(AppText.Block(),
          if (b) <>{@i18n("Contact blocked")}</>
          else <>{@i18n("Contact Unblocked")}</>)
      case {failure: s}:
        Notifications.error(AppText.Block(), <>{s}</>)
    }
  }
  client function do_block_contact(contact, _) {
    // if (Client.confirm(@i18n("Are you sure you want to block this contact?"))) {
      Button.loading(#block_contact_button)
      ContactController.block(contact, true, block_contact_callback)
    // }
  }
  client function do_unblock_contact(contact, _) {
    // if (Client.confirm(@i18n("Are you sure you want to unblock this contact?"))) {
      Button.loading(#block_contact_button)
      ContactController.block(contact, false, block_contact_callback)
    // }
  }

  /** {2} Deletion. */

  @async
  client function remove_contact_callback(res) {
    Button.reset(#remove_contact_button)
    match (res) {
      case {success: (contact)}:
        refresh_contacts()
        Notifications.info(AppText.contact(), <>{@i18n("removed")}</>)
        Dom.transform([#contact_viewer = <></>])
      case {failure: s}:
        Notifications.error(AppText.contact(), <>{s}</>)
    }
  }
  client function do_remove_contact(contact, _) {
    // if (Client.confirm(@i18n("Are you sure you want to remove this contact?"))) {
      Button.loading(#remove_contact_button)
      ContactController.remove(contact, remove_contact_callback)
    // }
  }

  /** {2} Profile picture selection. */

  client function upload_picture() {
    void
  }

  /** Choose a picture from PEPS database. */
  client function choose_picture(Contact.id id, _evt) {
    FileChooser.create({
      title: AppText.choose_file(),
      immediate: true,
      callback: {action: do_choose_picture(id, _, _), text: AppText.select() },
      exclude: [], custom
    })
  }
  client function do_choose_picture(Contact.id id, _key, selected) {
    match (selected) {
      case [img|_]:
        log("do_choose_picture: selected {img}")
        ContactController.Async.set_picture(id, img, change_picture(id, _))
      default: void
    }
  }
  client function change_picture(Contact.id id, res) {
    match (res) {
      case {success: dataUrl}: #{"{id}-picture"} = <img src={dataUrl} class="user-img"/>
      default: void
    }
  }

  /**
   * {2} Open.
   *
   * The user paramters indicate whether the contact originates from the list of team users,
   * or from the list of user contacts.
   */

  @async
  client function open_callback(res, clear) {
    if (clear) Notifications.clear()
    match (res) {
      case {success: html}:
        #contact_viewer = html
      case {failure: msg}:
        #contact_viewer = <>{msg}</>
    }
  }
  @async
  exposed function open_contact(Contact.id id, clear, bool user, bool edit) {
    res = if (user) ContactController.open_user(id) else ContactController.open(id)
    match (res) {
      case {success: contact}:
        html =
          edit_contact(contact, defaults)
          //if (edit && not(user)) edit_contact(contact)
          //else display_contact(contact, user)
        open_callback({success: html}, clear)
      case ~{failure}:
        open_callback(~{failure}, clear)
    }
  }
  client function do_open_contact(Contact.id id, bool user, bool edit, _) {
    // Notifications.loading()
    open_contact(id, true, user, edit)
  }

  function contact_actions(Contact.t contact) {
    blocked = contact.status == {blocked}
    block_cl = if (blocked) AppText.unlock() else AppText.lock()
    block_txt = if (blocked) AppText.Unblock() else AppText.Block()
    blocking_txt = if (blocked) AppText.Unblocking() else AppText.Blocking()
    block_act =
        if (blocked) do_unblock_contact(contact, _)
        else do_block_contact(contact, _)
    //edit_btn = <a id="block_contact_button" class="btn btn-sm btn-default" onclick={do_open_contact(contact.id, false, true, _)}>{AppText.Edit()}</a>

    <>
      <button type="button" id="block_contact_button" class="btn btn-sm btn-default"
            onclick={block_act}
            data-loading-text="{blocking_txt}"
            data-complete-text="{block_txt}"><i class="fa fa-lock-o"/> {block_txt}</button>
      <button type="button" id="remove_contact_button" class="btn btn-sm btn-default"
            onclick={do_remove_contact(contact, _)}
            data-loading-text="{AppText.Deleting()}"
            data-complete-text="{AppText.delete()}"><i class="fa fa-trash-o"/> {AppText.delete()}</button>
    </>
  }

  /** {1} Views: display and edit. */

  /**
   * Retrieve the contact profile picture.
   * @param chooser turn the image into a profile picture chooser.
   */
  protected function profile_picture(Contact.t contact, bool chooser) {
    src = match (contact.info.photos) {
      case [img|_]: <img src="/thumbnail/{img.elt}" class="user-img"/>
      default: <div class="user-img user-img-default"></div>
    }

    if (chooser)
      <div class="dropdown">
        <div id="{contact.id}-picture" class="pull-left dropdown-toggle" data-toggle="dropdown">
          {src}
        </div>
        {picture_dropdown(contact.id)}
      </div>
    else
      {src}
  }

  /** Selector for the profile picture. */
  function picture_dropdown(Contact.id id) {
    <ul class="dropdown-menu" role="menu">
      <li><a onclick={choose_picture(id, _)}>{AppText.choose_file()}</a></li>
    </ul>
  }

  /** Include to picture_dropdown <li><a>{AppText.upload_file()}</a></li> */

  /**
   * Display a contact (editing disabled).
   * @param user indicaters the origin of the contact. If the contact is a team user, then it can't be neither$
   *   edited nor blocked.
   */
  protected function display_contact(Contact.t contact, bool user) {
    blocked = contact.status == {blocked}
    block_cl = if (blocked) AppText.unlock() else AppText.lock()
    block_txt = if (blocked) AppText.Unblock() else AppText.Block()
    blocking_txt = if (blocked) AppText.Unblocking() else AppText.Blocking()
    block_act =
      if (blocked) do_unblock_contact(contact, _)
      else do_block_contact(contact, _)
    // Render a block of items.
    // The category is not displayed if the list is empty.
    function render(title, items, render) {
      if (items == []) <></>
      else {
        items = List.fold(function (item, acc) {
          acc <+> <p><small>{item.kind}</small> {render(item.elt)}</p>
        }, items, <></>)
        <address>
          <strong>{title}</strong>
          {items}
        </address>
      }
    }

    picture = profile_picture(contact, true)
    phoneNumbers = render("Phone", contact.info.phoneNumbers, identity)
    addresses = render("Address", contact.info.addresses, _.formatted)
    emails =
      // Adding weight and sorting.
      List.map(function (item) { ~{item, weight: Contact.weight(contact.owner, item.elt)} }, contact.info.emails) |>
      List.sort_by(_.weight, _) |> List.map(_.item, _) |> List.rev |>
      render("Email", _, Email.address_to_string)

    <div class="contact">
      <div class="contact_summary">
        <div class="contact-heading">
          {picture}
          <h3 class="pull-left">{Contact.name(contact)}</h3>
          {if (user) <></> else contact_actions(contact)}
        </div>
      </div>
      {phoneNumbers}
      {emails}
      {addresses}
    </div>
  }

  /**
   * Contact edition and related functions.
   *
   * Inputs must be extracted with dom functions.
   * It is possible to gather the ids of each input element, since they are provided by
   * the containers with class [multiple-input]. The different elements have the following ids:
   *   - input: [{id}-input]
   *   - kind: [{id}-kind]
   */
  private function extract(string id, (string -> option('a)) parse) {
    Dom.select_inside(#{"{id}"}, Dom.select_class("multiple-input")) |>
    Dom.fold(function (dom, acc) {
      id = Dom.get_id(dom)
      kind = Dom.get_text(#{"{id}-kind"})
      input = Dom.get_value(#{"{id}-input"})
      if (String.trim(input) == "") acc
      else
        match (parse(input)) {
          case {some: elt}:
            {acc with items: [~{elt, kind}|acc.items]}
          default:
            {acc with errors: [input|acc.errors]}
        }
    },
    {items: [], errors: []}, _)
  }

  /** Default kinds. */
  both kinds = ["work", "home", "other"]

  /** Group creation. */
  both function group(id, label, items, render) {
    inputs = List.map(function (item) {
       ~{ id: Dom.fresh_id(), kinds, ~label,
          defaults: { kind: item.kind, input: some(render(item.elt)) } }
      }, items)
   ~{ ~id, label, kinds, addnew: false,
      defaults: { ~inputs, kind: "work" } }
  }

  /** Dynamically add new groups. */
  client function add_group(grp, _evt) {
    dom = #{"{grp}-group"}
    options = ~{
      id: "{grp}-group", label: String.capitalize(grp),
      kinds, addnew: true,
      defaults: { inputs: [], kind: "work" }
    }
    if (Dom.is_empty(dom)) {
      newgroup = Form.group(options) |> Dom.of_xhtml
      Dom.put_before(#extra_field, newgroup) |> ignore
    }else
      Form.add_input(options)
  }

  /**
   * Build the contact edition view.
   * @param showactions reveal the contact actions (edit, block, delete).
   */
  both function contact_editor(contact, picture, ContactView.options options) {
    blocked = contact.status == {blocked}
    block_cl = if (blocked) AppText.unlock() else AppText.lock()
    block_txt = if (blocked) AppText.Unblock() else AppText.Block()
    block_act =
      if (blocked) do_unblock_contact(contact, _)
      else do_block_contact(contact, _)
    name = contact.info.displayName
    heading =
      if (contact.info.displayName == "") <>{@i18n("Create a new contact")}</>
      else <>{name}</>

    // picture = profile_picture(contact, true)
    phone_group = group("phone-group", "Phone", contact.info.phoneNumbers, identity)
    address_group = group("address-group", "Address", contact.info.addresses, _.formatted)
    company_group = group("company-group", "Company", contact.info.organizations, _.name)
    email_group = group("email-group", "Email", contact.info.emails, Email.address_to_string)

    actions =
      if (options.actions) <div class="pull-right btn-group">{contact_actions(contact)}</div>
      else <></>
    cancel =
      if (options.actions) WB.Button.make({button: <>{AppText.Cancel()}</>, callback: do_open_contact(contact.id, false, false, _)}, [{`default`}])
      else <></>
    reset = <></>

    add_field =
      (<div class="dropdown">
        <a data-toggle="dropdown" class="btn btn-default dropdown-toggle">{@i18n("Add field")}</a>
        <ul class="dropdown-menu">
          <li><a onclick={add_group("email", _)}>{AppText.email()}</a></li>
          <li><a onclick={add_group("phone", _)}>{@i18n("Phone")}</a></li>
          <li><a onclick={add_group("address", _)}>{@i18n("Address")}</a></li>
          <li><a onclick={add_group("company", _)}>{@i18n("Company")}</a></li>
        </ul>
      </div>)
    form =
      Form.wrapper(
        <div class="pane-heading">
          {actions}
          {picture}
          <h3>{heading}</h3>
        </div> <+>
        Form.line({Form.Default.line with label: AppText.name(), id: "contact_name", value: name}) <+>
        Form.group(phone_group) <+>
        Form.group(email_group) <+>
        Form.group(address_group) <+>
        Form.group(company_group) <+>
        <>
        <div id="extra_field" class="extra-field form-group">
          {add_field}
        </div>
        <div class="form-group">
          {(WB.Button.make({button: <>{@i18n("Save changes")}</>, callback: do_save(contact, options.format, _)}, [{primary}])
            |> Xhtml.add_attribute_unsafe("data-complete-text", @i18n("Save changes"), _)
            |> Xhtml.add_attribute_unsafe("data-loading-text", AppText.saving(), _)
            |> Xhtml.add_id(some("save_contact_button"), _))
          }
        </div></>
      , false)

    <div class="contact">
      <div class="contact_summary">
        {form}
      </div>
    </div>
  }

  protected function edit_contact(contact, ContactView.options options) {
    // Sort the email addresses by importance.
    emails =
      List.map(function (item) { ~{item, weight: Contact.weight(contact.owner, item.elt)} }, contact.info.emails) |>
      List.sort_by(_.weight, _) |> List.map(_.item, _) |> List.rev
    contact = {contact with info.emails: emails}
    contact_editor(contact, profile_picture(contact, true), options)
  }

  protected function build_contacts(list(Contact.client_contact) contacts, bool user) {
    List.map(function (ccontact) {
      contact = ccontact.contact
      name =
        match (ccontact.highlighted_name) {
          case {some: name}: Xhtml.of_string_unsafe(name)
          case {none}:
            match (ccontact.highlighted_emails) {
              case {some: emails}: Xhtml.of_string_unsafe(emails)
              case {none}: <>{Contact.name(contact)}</>
            }
        }
      picture = profile_picture(contact, false)
      onclick = do_open_contact(contact.id, user, false, _)

      // FIXME: require key to call signature
      // Also : move this action to listed email addresses (instead of user icon).
      // ondblclick={ComposeView.write_to(email, _, "" /* signature */ )}/>
      elt =
        picture <+>
        <span class="contact">{name}</span> <+>
        ( if (contact.status == {blocked}) <span class="fa fa-lg fa-ban"/>
          else <></> )
      // Return list item with onclick handler.
      (elt, onclick)
    }, contacts) |>
    ListGroup.make(_, AppText.no_contacts())
  }

  protected function build(Login.state state, Path.t path) {
    if (not(Login.is_logged(state)))
      Content.login_please
    else {
      contacts = match (path) {
        // Display contacts from a user team.
        case ["teams", team | _]:
          match (Team.get_key(team)) {
            case {none}: Content.non_existent_resource
            case {some: team}:
              // Checks.
              if (not(User.is_in_team(state.key, team))) Content.not_allowed_resource
              else {
                // Fetch the team users and transform into contacts.
                // FIXME: make a lightweight page-based version of this.
                users = User.get_team_users([team]) |> Iter.map(_.key, _) |> Iter.to_list
                contacts = Contact.list(users)  |> List.map(Contact.to_client_contact, _)
                build_contacts(contacts, true)
              }
          }
        // Others: display contact list.
        default:
          contacts = Contact.get_all(state.key) |> List.map(Contact.to_client_contact, _)
          build_contacts(contacts, false)
      }
      // Build the html list.
      <div id=#contacts_list_outer class="pane-left">
        <div class="pane-heading">
          <h3>{AppText.contacts()}</h3>
        </div>
        <div id=#contacts_list>{contacts}</div>
      </div>
      <div id=#contact_viewer class="contact_viewer pane-right"/>
    }
  }

}
