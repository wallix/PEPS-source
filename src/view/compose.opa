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

/** {1} Client variables. */

type ComposeModal.init = {
  thread: option(Message.id)
  mid: Message.id
  subject: string
  content: string
  security: Label.id
  labels: list(Label.Client.label)
  to: list(Mail.address)
  cc: list(Mail.address)
  bcc: list(Mail.address)
  reedit: bool
  files: list(File.id)
}

ComposeView = {{

  log = Log.notice("[ComposeView]", _)
  toggle_id(id) =
  _ ->
    _ = Dom.transition(id, Dom.Effect.toggle())
    void

  /**
   * {1} Construction of the modal.
   *
   * A new modal is created for each message to write, and distroyed when the modal is closed.
   */

  /**
   * Default configuration.
   * NB: the message id should be reset.
   */
  defaults = {
    thread= none mid= Message.dummy
    subject= ""
    content= ""
    security= 1 // Open
    labels= []
    to= [] cc= [] bcc= []
    reedit= false
    files=[]
  }

  /**
   * Destroy a modal.
   * It is also necessary to release the lock on the message, in case of reedition.
   */
  @client destroy(id: string, mid: string, _evt: Dom.event) =
    do MessageController.unlock(mid)
    Dom.remove(#{id})

  /** Toggle the compose modal fullscreen mode. */
  @client fullscreen(id: string, _evt: Dom.event) =
    // modal = #{id} Select the whole modal
    dialog = Dom.select_inside(#{id}, Dom.select_class("modal-dialog")) // Select the modal dialog only.
    content = Dom.select_inside(#{id}, Dom.select_class("modal-content")) // Select the modal content only.
    do Misc.toggle("{id}-fullscreen-toggle", "fa-expand", "fa-compress")
    if (Dom.has_class(dialog, "modal-fullscreen")) then
      do Dom.remove_class(dialog, "modal-fullscreen")
      Dom.set_height(content, AppConfig.compose_height)
    else
      do Dom.add_class(dialog, "modal-fullscreen")
      Dom.set_height(content, Dom.get_height(#main))

  /**
   * Create a compose modal, add it to the main dom element, and bind it
   * so that is is destroyed when closed.
   * The new modal is assigned a fresh dom id.
   *
   * @param init the configuration of the modal.
   * @return the dom id of the modal.
   */
  @publish create(title: string, init: ComposeModal.init) =
    state = Login.get_state()
    id = Dom.fresh_id()
    fullscreen = <a id="{id}-fullscreen-toggle" class="pull-right fa fa-expand" onclick={fullscreen(id, _)}></a>
    modal =
      Modal.make(id,
        <>{title}{fullscreen}</>,
        build_compose(state, id, init),
        compose_buttons(state, id, init),
        { Modal.default_options with backdrop = false static = false keyboard = false }
      ) |>
      Xhtml.add_attribute_unsafe("class", "compose-modal", _)
    do insert(id, init.mid, Xhtml.precompile(modal))
    id

  /** Insert the created modal into the view, and add the nccessary bindings. */
  @client insert(id, mid, modal) =
    initscript =
      <script id="{id}-init" type="text/javascript">
        {Xhtml.of_string_unsafe("init_compose('#{id}');")}
      </script>
    do #main -<- modal // PREPEND the modal so it appears behind other modals (e.g. file chooser).
    do #{id} +<- initscript // NB: must be upload AFTER the modal, else the script can not be executed correctly.
    do Modal.show(#{id})
    do Dom.bind(#{id}, {custom= "hidden.bs.modal"}, destroy(id, mid, _)) |> ignore
    Scheduler.sleep(500, -> Dom.give_focus(#{"{id}-to-input"}))


  /** {2} Mail recipients. */

  Recipient = {{

    /** Remove a recipient. Triggered by clicking on the 'close' icon in recipients label. */
    @private @client remove(id: string, eltid: string, _evt) =
      do Dom.remove(#{eltid})
      adjust_input_width(id)

    /** Remove the last recipient of the given containr. Triggered by backspace in an empty textarea. */
    @private @client remove_last(id: string) =
      last =
        Dom.select_inside(#{"{id}-list"}, Dom.select_class("recipient")) |>
        Dom.select_last_one
      do Dom.remove(last)
      adjust_input_width(id)

    /** Parse a recipient list. */
    @client parse(id: string, input: string) =
      String.explode(",", input) |>
      List.map(String.trim, _) |>
      List.fold(input, acc ->
        if input == "" then acc
        else
          match (MessageController.identify(input)) with
            | {unspecified=addr} -> acc <+> recipient(id, addr, addr, input, false)
            | {external=email} -> acc <+> recipient(id, Email.to_name(email), Email.address_to_string(email.address), input, false)
            | {internal=~{email team ...}} -> acc <+> recipient(id, Email.to_name(email), Email.address_to_string(email.address), input, team)
          end, _, <></>)

    /** Build a recipient encapsluated in a label, that can be removed easily. */
    @private @both recipient(id: string, name: string, address: string, email: string, team: bool) =
      eltid = Dom.fresh_id()
      labelclass =
        if (team) then ["label", "label-team"]
        else ["label", "label-recipient"]
      <div id={eltid} data-name={name} class="recipient pull-left">
        <span title={address} rel="tooltip" data-placement="bottom" class={labelclass}>
          {name}
          <a onclick={remove(id, eltid, _)} class="fa fa-times" title={AppText.remove()}></a>
        </span>
        <input id="email" type="hidden" value={email}/>
      </div>

    @private @both recipient_of_addr(id: string, addr) =
      team = false
      match (addr) with
        | {internal= ~{email key team}}
        | {external= email} ->
          name = Email.to_name(email)
          address = Email.address_to_string(email.address)
          email = Email.to_string(email)
          recipient(id, name, address, email, team)
        | {unspecified= email} ->
          recipient(id, email, email, email, team)
      end

    /**
     * Adjust the width of the input element, depending on the recipients already entered,
     * and the value of the input.
     */
    @private @client adjust_input_width(id: string) =
      listid = "{id}-list"
      inputid = "{id}-input"

      recipients = Dom.select_inside(#{listid}, Dom.select_class("recipient"))
      divwidth = Dom.get_inner_width(#{"{id}-inner"})
      do log("Div width: {divwidth}")
      do log("Selected recipients: {Dom.length(recipients)}")
      // Compute cumulated width of last line of recipients.
      linewidth = Dom.fold(recipient, width ->
        rwidth = Dom.get_width(recipient)
        if (width+rwidth > divwidth) then
          do log("New line ({width})")
          rwidth
        else width+rwidth
      , 0, recipients)
      do log("Last line: {linewidth}")
      width =
        if (divwidth-linewidth < 30) then divwidth
        else divwidth-linewidth-5
      do log("Adjusted width: {width}")
      Dom.set_width(#{inputid}, width)
      // Dom.set_attribute_unsafe(#{inputid}, "style", "width: {width}px")


    /**
     * Convert the input in a textarea, and add it to the list of recipients.
     * @param listid the id of the recipients' container.
     */
    @private @client add(id: string, value: string) =
      _ = Dom.put_before(#{"{id}-input"}, Dom.of_xhtml(parse(id, value)))
      adjust_input_width(id)

    /**
     * Set the list if recipients.
     * @param recipients addresses in the type {Mail.address}
     */
    // set_recipients(id: string, recipients) =
    //   do Dom.clear_value(#{"{id}-input"})
    //   recipients = List.fold(recipient, acc -> acc <+> recipient_of_addr(id, recipient), recipients, <></>)
    //   do #{"{id}-list"} +<- recipients
    //   adjust_input_width(id)


    /** Manage changes to the recipient list. */
    @private @client input(id: string, evt) =
      inputid = "{id}-input"
      value = Dom.get_value(#{inputid}) |> String.trim
      match (evt.key_code) with
        // Backspace.
        | {some= 8} ->
          if (value == "" && evt.kind == {keydown}) then remove_last(id)
        // Comma and Newline.
        | {some= 188}
        | {some= 13} ->
          if (value != "" && evt.kind == {keyup}) then
            do Dom.set_value(#{inputid}, "")
            add(id, value)
        | _ -> void
      end

    /**
     * Build a recipient box. The used dom identifiers are:
     *  - {id}-recipient-box for the topmost container
     *  - {id}-list for the labels' list
     *  - {id}-input for the input element
     *
     * @param init list of initial recipients.
     */
    box(id: string, name: string, init, ccbcc: bool, ccid: string, bccid: string) =
      listid = "{id}-list"
      inputid = "{id}-input"
      // Compute the list of initial recipients.
      init = List.fold(addr, acc -> acc <+> recipient_of_addr(id, addr), init, <></>)
      toggle =
        if (ccbcc) then
          <label class="control-label" onclick={toggle_id(#{ccid})}>{AppText.Cc()}</label>
          <label class="control-label" onclick={toggle_id(#{bccid})}>{AppText.Bcc()}</label>
        else <></>
      style = if (ccbcc) then "" else "display:none;"
      <div id="{id}-recipient-box" class="form-group" style="{style}">
        <div class="frow">
          <label class="control-label fcol" for={inputid}>{name}:</label>
          <div id="{id}-inner" class="fcol fcol-lg">
            <div class="recipients-list pull-left" id={listid}>
              {init}
              <input id={inputid} rows="1" class="recipients-field form-control pull-left [addresses]"
                spellcheck="false" autocomplete="off"
                onkeydown={input(id, _)}
                onkeyup={input(id, _)}/>
            </div>
          </div>
          <div class="fcol">
            <div class="fcol-right">
              {toggle}
            </div>
          </div>
        </div>
      </div>

    /** Extract the list of recipients of a box. */
    @client get(id: string) =
      // From the list of recipients.
      recipients =
        Dom.select_id("{id}-list") |>
        Dom.select_children |>
        Dom.select_inside(_, Dom.select_id("email"))
      emails = Dom.fold(dom, acc -> [Dom.get_value(dom)|acc], [], recipients)
      // Additional recipients from the input.
      Dom.get_value(#{"{id}-input"}) |>
      String.explode(",", _) |> List.map(String.trim, _) |>
      List.fold(value, acc ->
        if value == "" then acc
        else [value|acc], _, emails)

    /** Clear the recipients list and input of a box. */
    clear(id: string) =
      do Dom.clear_value(#{"{id}-input"})
      #{"{id}-list"} <- <></>

  }}

  /** {2} Modal body. */

  build_compose(state: Login.state, id: string, init: ComposeModal.init) =
    <div id="{id}-notification"/> <+>
    Form.wrapper(
      Recipient.box("{id}-to", AppText.To(), init.to, true, "{id}-cc-recipient-box", "{id}-bcc-recipient-box") <+>
      Recipient.box("{id}-cc", AppText.Cc(), init.cc, false, "", "") <+>
      Recipient.box("{id}-bcc", AppText.Bcc(), init.bcc, false, "", "") <+>
      <div class="form-group">
        <div class="frow">
          <label class="control-label fcol" for="{id}-subject">{AppText.Subject()}:</label>
          <div class="fcol fcol-lg">
            <input id="{id}-subject" type="text" class="form-control [subject]" autocomplete="off" value="{init.subject}"/>
          </div>
        </div>
      </div>
      <div class="form-group">
        <div class="frow">
          {(if AppConfig.has_security_labels then
            <label class="control-label fcol">{AppText.classification()}:</label>
            <div class="fcol fcol-md">{LabelView.Class.selector("{id}-class", state.key, init.security)}</div>
          else <></>)}
          <label class="control-label fcol">{AppText.labels()}:</label>
          <div class="fcol fcol-md">{LabelView.Personal.selector("{id}-labels", state.key, init.labels)}</div>
        </div>
      </div> <+>
      UploadView.attachment_box(state, id, init.files) <+>
      <div class="form-group">
        <textarea id="{id}-content" class="form-control" rows="8">{init.content}</textarea>
      </div>
    , true)

  compose_buttons(state: Login.state, id: string, init: ComposeModal.init) =
    (savetext, saveloading, sendtext, sendloading) =
      if (init.reedit) then (@i18n("Revert to draft"), AppText.saving(), @i18n("Modify"), AppText.Sending())
      else                  (@i18n("Save as draft"), AppText.saving(), AppText.Send(), AppText.Sending())
    (WB.Button.make({button= <>{savetext}</> callback= do_write(id, "{id}-save", true, init, _)}, [{`default`}])
      |> Xhtml.add_attribute_unsafe("data-loading-text", saveloading, _)
      |> Xhtml.add_attribute_unsafe("data-complete-text", savetext, _)
      |> Xhtml.add_id(some("{id}-save"), _)) <+>
    (WB.Button.make({button=<>{sendtext}</> callback= do_write(id, "{id}-send", false, init, _)}, [{primary}])
      |> Xhtml.add_attribute_unsafe("data-loading-text", sendloading, _)
      |> Xhtml.add_attribute_unsafe("data-complete-text", sendtext, _)
      |> Xhtml.add_id(some("{id}-send"), _))

  /** {2} Callbacks. */

  @client @async
  send_callback(id: string, res) =
    match (res) with
    | {success= (status, encrypted)} ->
      do FileView.Common.reencrypt(status.owner, encrypted)
      do Modal.hide(#{id}) |> ignore // Triggers the destruction of the modal.
      UploadView.clear(id) // Remove attachments from local reference.
      // Content.refresh()
    | {failure=(msg, errors)} ->
      do Notifications.notify("{id}-notification", AppText.Send_failure(), <>{msg}</>, {error})
      // do Content.clear_modal_errors()
      do List.iter(id -> Dom.add_class(id, "error"), errors)
      Button.reset(#{"{id}-send"}) // Reset send button.
    end

  @client @async
  save_callback(id: string, res) =
    match (res) with
    | {success=(status, encrypted)} ->
      do FileView.Common.reencrypt(status.owner, encrypted)
      do Modal.hide(#{id}) |> ignore // Triggers the destruction of the modal.
      do UploadView.clear(id) // Remove attachments from local reference.
      Content.refresh()
    | {failure=(msg, errors)} ->
      do Notifications.notify("{id}-notification", AppText.Save_failure(), <>{msg}</>, {error})
      do List.iter(id -> Dom.add_class(id, "error"), errors)
      Button.reset(#{"{id}-save"})
    end

  @client reedit_callback(id, res) : void =
    match res with
    | {success=msg} -> Notifications.notify("{id}-notification", "{AppText.Reedit()} {id}", <>{msg}</>, {success})
    | {info=msg} -> Notifications.notify("{id}-notification", "{AppText.Reedit()} {id}", <>{msg}</>, {info})
    | {error=msg} -> Notifications.notify("{id}-notification", "{AppText.Reedit()} {id}", <>{msg}</>, {error})
    | {null} -> void
    end

  /**
   * Send the message. If the security label enforces message encryption, the content is encrypted
   * BEFORE being sent to the server. The message key pair encryption is performed server side.
   */
  @client
  do_write_aux(id, btnid, draft, init, files) =
    to = Recipient.get("{id}-to")
    cc = Recipient.get("{id}-cc")
    bcc = Recipient.get("{id}-bcc")
    subject = Dom.get_value(#{"{id}-subject"})
    labels = LabelView.Personal.extract("{id}-labels")
    security = Dom.get_attribute_unsafe(#{"{id}-class"}, "title")
    content = Dom.get_value(#{"{id}-content"})
    mtype =
      if draft then {draft}
      else {send}
    callback =
      if draft then save_callback(id, _)
      else send_callback(id, _)

    // Parse main parameters.
    match (MessageController.sendBefore(to, cc, bcc, security)) with
    | ~{security encryption to cc bcc key} ->
      if (encryption) then
        // Message encryption is enforced by the chosen security label.
        // First extract the user's secret key.
        UserView.SecretKey.prompt(key, @i18n("PEPS requires your password to encrypt this message."), secretKey ->
          match (secretKey) with
          | {some= secretKey} ->
            // Generate a keyPair for the message.
            keyPair = TweetNacl.Box.keyPair()
            nonce = TweetNacl.randomBytes(TweetNacl.Box.nonceLength)
            do log("write: encrypting message")
            do log("write: userSecretKey={Uint8Array.encodeBase64(secretKey)}")
            do log("write: messageSecretKey={Uint8Array.encodeBase64(keyPair.secretKey)}")
            do log("write: messagePublicKey={Uint8Array.encodeBase64(keyPair.publicKey)}")
            // Encode the content.
            content =
              content = Uint8Array.decodeUTF8(content)
              TweetNacl.Box.box(content, nonce, keyPair.publicKey, secretKey) |>
              Uint8Array.encodeBase64
            // Message encryption: nonce + keyPair.
            encryption = {
              nonce= Uint8Array.encodeBase64(nonce)
              secretKey= Uint8Array.encodeBase64(keyPair.secretKey)
              publicKey= Uint8Array.encodeBase64(keyPair.publicKey)
            }
            MessageController.Async.send(init.mid, init.thread, to, cc, bcc, subject, labels, security, content, files, mtype, init.reedit, encryption, callback)
          | _ ->
            callback({failure= (@i18n("Unable to encrypt this message, retry later or choose a different label"), [])})
          end)
      else
        MessageController.Async.send(init.mid, init.thread, to, cc, bcc, subject, labels, security, content, files, mtype, init.reedit, {none}, callback)

    | ~{failure} -> callback(~{failure})
    end

  @client
  do_write_deferred(id, btnid, draft, init) =
    files = AttachedRef.list(id)
    subject = Dom.get_value(#{"{id}-subject"})
    security = Dom.get_attribute_unsafe(#{"{id}-class"}, "title")
    origin = {email=init.mid} : File.origin
    files = List.map(file ->
      match file.origin with
      | {internal} | {email=_} -> {file with ~origin}
      | _ -> file, files)
    if draft || subject != "" ||
        Utils.ask("", @i18n("No subject defined. Continue?")) then
      if (files == []) then
        do_write_aux(id, btnid, draft, init, [])
      else
        FSController.upload(files, {right= ["Attached"]}, security,
          | {success = (_, files)} -> do_write_aux(id, btnid, draft, init, files)
          | x -> do_write_aux(id, btnid, draft, init, [])
        )
    else Button.reset(#{btnid})

  /** Prepare the message for sending. */
  @client
  do_write(id, btnid, draft, init, event) =
    do Button.loading(#{btnid})
    do #{"{id}-notification"} <- ""
    security = Dom.get_attribute_unsafe(#{"{id}-class"}, "title")
    if security == "" then log("do_write: undefined security label")
    else Scheduler.sleep(500, -> do_write_deferred(id, btnid, draft, init))

  /** {2} Main compose view calls: reply, reedit, forward, new. */

  /** Message edition (common between draft edition and message reedition). */
  edit(init: ComposeModal.init) =
    content = Dom.get_text(#{"{init.mid}-content"}) // Extract previous content from message view.
    init = {init with ~content}
    create(AppText.reedit_message(), init) |> ignore

  /** Message reedition. */
  @publish reedit(init: ComposeModal.init) =
    mid = init.mid
    state = Login.get_state()
    if (Message.lock(mid, state.key)) then
      do edit({init with reedit=true})
      reedit_callback(mid, {null})
    else
      reedit_callback(mid, {error= @i18n("Can't obtain lock, mail has been opened")})

  /** Compose a new message. */
  @client new(sgn, _evt) =
    init = {defaults with content=sgn mid=Message.genid()}
    create(AppText.new_message(), init) |> ignore

  /** Compose a mail addressed to a given user. */
  @client write_to(email, sgn, _evt) =
    init = {defaults with content=sgn to=[email]}
    create(AppText.new_message(), init) |> ignore

  /**
   * Message forwarding.
   * TODO: add the shared labels of the initial message ?
   */
  @client forward(init: ComposeModal.init, modclass, sgn, _evt) =
    subject =
      if String.has_prefix("{AppText.Fwd()}:", init.subject) then init.subject
      else "{AppText.Fwd()}: {init.subject}"
    content = Dom.get_text(#{"{init.mid}-content"}) // Content extracted from message view.
    content = "

{sgn}
{@i18n("Forwarded message")}:
{content}"
    init = ~{defaults with mid=Message.genid() subject content security=init.security files=init.files}
    id = create(AppText.new_message(), init)
    if (not(modclass)) then Dom.remove_attribute(#{"{id}-class"}, "onclick")

  /** Reply to a message. */
  @client reply(init, from, created, recipients, all: bool, modclass, sgn, _evt) =
    to = if all then recipients else [from]
    cc = if not(all) then [] else init.cc
    from = Message.Address.name(from)
    subject =
      if String.has_prefix("{AppText.Re()}:", init.subject) then init.subject
      else "{AppText.Re()}: {init.subject}"
    date = Date.to_formatted_string(Date.generate_printer("%d.%m.%y %H:%M"), created)
    content = Dom.get_text(#{"{init.mid}-content"}) // Content extracted from message view.
    content = AppText.print_wrote(date, from, content, sgn)
    thread = init.thread
    init = ~{defaults with mid=Message.genid() content subject to cc security=init.security labels=init.labels thread}
    id = create(AppText.new_message(), init)
    if (not(modclass)) then Dom.remove_attribute(#{"{id}-class"}, "onclick")

  /** Open a minimal reply form within the message view. */
  @client open_reply(init, from, created, recipients, modclass, sgn, _evt) =
    mid = init.mid
    all = not(Dom.has_class(#{"{mid}-reply-switch"}, "fa-reply-all"))
    to = if all then recipients else [from]
    cc = if all then init.cc else []
    from = Message.Address.name(from)
    subject =
      if String.has_prefix("{AppText.Re()}:", init.subject) then init.subject
      else "{AppText.Re()}: {init.subject}"
    date = Date.to_formatted_string(Date.generate_printer("%d.%m.%y %H:%M"), created)
    content = Dom.get_text(#{"{init.mid}-content"}) // Content is extracted from the message view.
    newcontent = Dom.get_value(#{"{mid}-reply-text"})
    content = newcontent ^ AppText.print_wrote(date, from, content, sgn)
    init = ~{defaults with mid=Message.genid() content subject to cc security=init.security labels=init.labels}
    id = create(AppText.new_message(), init)
    do MessageView.Reply.cancel(mid, _evt)
    if (not(modclass)) then Dom.remove_attribute(#{"{id}-class"}, "onclick")

}}
