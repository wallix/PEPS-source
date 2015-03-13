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

/** Pre-format the file for attachment display. */
type MessageView.file = {
  id: RawFile.id
  name: string
  mimetype: string
  size: int
  thumbnail : option(string) // A dataUrl if defined.
  link: string
}

MessageView = {{

  /** {1} Utils. */

  log = Log.notice("[MessageView]", _)
  debug = Log.debug("[MessageView]", _)
  error = Log.error("[MessageView]", _)

  sb_message_parser = parser "sb_message_" id=(.*) -> Text.to_string(id) |> @toplevel.Message.midofs

  /** {2} Operations on addresses. */

  /**
   * Format a list of Message.Address.
   * @return an html list, ready for insertion into the document.
   */
  @private addresses_list(mid, addresses, limit, nameonly) =
    if addresses == [] then <>[{@i18n("No Recipient")}]</>
    else
      length = List.length(addresses)
      (addrs, toggle) =
        match (limit) with
        | {some= limit} ->
          if (length > limit) then (List.take(limit, addresses), [<span onclick={toggle_infos_indirect(mid, _)}>...</span>])
          else (addresses, [])
        | _ -> (addresses, [])
        end

      list = List.map(@toplevel.Message.Address.to_html(_, none, nameonly), addrs) |> List.intersperse(<>, </>, _)
      WB.List.unstyled(list ++ toggle)

  /**
   * Find a profile picture applicable to the provided address. The following possibilities
   * are tried in turn:
   *  - if contact exists with a profile picture, return it
   *  - else if internal address, and user has a profile picture, return it
   *  - else return a default picture.
   */
  @server_private userimg(key: User.key, addr: Mail.address) =
    ofcontact =
      @toplevel.Message.Address.email(addr) |>
      Option.bind(email -> Contact.find(key, email.address), _) |>
      Option.bind(info -> Contact.get_picture(info.contact), _) |>
      Option.bind(RawFile.get_thumbnail, _)
    match (ofcontact) with
    | {some= thumbnail} -> {some= thumbnail}
    | _ ->
      @toplevel.Message.Address.key(addr) |>
      Option.bind(User.get_picture, _) |>
      Option.bind(RawFile.get_thumbnail, _)
    end

  /** {2} File attachments. */

  /** Build the icon of a file attachment, to be inserted in the drop zone. */
  @server_private build_attachment(id, name, size, thumbnail, link) =
    // Fetch preview.
    action = <div class="file_action"><i class="fa fa-download-o"/></div>
    content =
      <div class="file-attached-content" title="Download {name}">
        <div class="name">{Utils.string_limit(35, name)}</div>
        <small class="size">{Utils.print_size(size)}</small>
      </div>
    icon =
      match (thumbnail) with
      | {some= picture} -> <div class="fimg-thumbnail"><img src={picture}/>{action}{content}</div>
      | _ -> <div class="file-thumbnail"><div class="file-icon"><i class="fa fa-file-o"/></div>{action}{content}</div>
      end
    // Build icon.
    <a href="{link}" class="file-attached pull-left fade in">
      {icon}
    </a>

  /** Build all message attachments. */
  @server_private build_attachments(files) =
    List.fold(file, list ->
      list <+>
      ( match (file) with
        | {some= ~{id; name; mimetype; size; thumbnail; link}} ->
          build_attachment(id, name, size, thumbnail, link)
        | _ -> <span>-deleted-</span> ),
      files, <></>)

  /** Fetch the metadata of a message attachment. */
  @server_private get_file(mid: Message.id, fid: File.id): option(MessageView.file) =
    match File.get_raw(fid) with
    | {some=raw} ->
      thumbnail =
        match (raw.thumbnail) with
        | {some= _thumbnail} -> some("/thumbnail/{raw.id}")
        | _ -> none
        end
      {some= ~{
        id= raw.id; name= raw.name;
        mimetype= raw.mimetype; size= raw.size;
        thumbnail= thumbnail; link= RawFile.makeURI(raw.id, raw.name);
      }}
    | _ -> none
    end

  /** Idem, applied to a list of file attachments. */
  @server_private
  get_files(mid: Message.id, files) =
    List.map(get_file(mid, _), files)

  /**
   * {1} Actions bound to elements of the message display.
   *
   * Those actions can be separated into three groups, depending on the part of the
   * message they apply to: message info panel, quick reply, others.
   *
   * {2} Message information.
   */

  /**
   * {3} Label management.
   *
   * This module contains the implementation of all the methods linked to
   * the label line of the message info: edition of the set and display of the list
   * of selected labels.
   */

  Labels = {{

    /** Refresh the lisf of message labels. */
    @private @publish refresh(key, res) =
      match (res) with
        | {success= (header, status)} ->
          labels = Label.to_client_list(header.labels ++ status.labels)
          callback = {
            onclick= remove(header.id, key, _, _, _)
            icon= "times"
            title= @i18n("Remove")
          }
          line = List.map(LabelView.make_label(_, {some= callback}), labels)
          #{"{header.id}-labels-list"} <- WB.List.unstyled(line)
        | {failure= msg} ->
          Notifications.error(@i18n("Message label failure"), <>{msg}</>)
      end

    /**
     * Remove a label from the current message.
     * Action associated with selected labels.
     */
    @private @client remove(mid: Message.id, key: User.key, _domid: string, id: Label.id, _evt) =
      MessageController.Async.update_labels(mid, [], [id], refresh(key, _))

    /** Add personal labels to recevied messages. */
    @private @client add(mid: Message.id, key: User.key, id: Label.id, _evt) =
      MessageController.Async.update_labels(mid, [id], [], refresh(key, _))

    /** Build a dropdown menu containing the labels that can be used by the current user. */
    @server_private dropdown(mid: Message.id, key: User.key) =
      usable = Label.list(key, {shared}) // List of usable labels.
      list = List.fold(label, list ->
        clabel = Label.full_to_client(label) |> LabelView.make_label(_, none)
        list <+> <li onclick={add(mid, key, label.id, _)}>{clabel}</li>
      , usable, <></>)
      <ul class="dropdown-menu dropup label-chooser-dropdown">{list}</ul>

    /** Build the inital selection of labels. */
    @server_private @expand line(mid: Message.id, key: User.key, labels) =
      callback = {
        onclick= remove(mid, key, _, _, _)
        icon= "times"
        title= @i18n("Remove")
      }
      List.map(LabelView.make_label(_, {some= callback}), labels) |> WB.List.unstyled

  }} // END LABELS



  /**
   * {3} Status update.
   *
   * This module manages the display and refreshing of the status line
   * showing under in the message info.
   */

  Status = {{

    /** The refresh button. */
    @private @client refresh(info) = <a onclick={update(info, _)} title="{AppText.Refresh()}" class="fa fa-repeat-circle-o"></a>
    /** The modify button. */
    @private @client modify(info) =
      <span>
        {@i18n("Not read yet.")}
        <a onclick={reedit(info, _)}>{@i18n("Modify message")}</a>
      </span>
    /** Read / unread spans. */
    @private @client @expand read(name) = <span><span class="email-read">{@i18n("Read by")}</span> {name}</span>
    @private @client @expand unread(name) = <span><span class="email-unread">{@i18n("Unread by")}</span> {name}</span>

    /** The reedition handler. */
    @private @client reedit(info, _evt) = ComposeView.reedit(info)

    /**
     * Refresh the status view with updated information obtained from
     * the function {Status.update}
     */
    @client set(statuses, noteams, external, info): void =
      // Separate statuses into read and unread.
      statuses = List.fold((name, opened), statuses ->
        if (opened) then {statuses with read= [name | statuses.read]}
        else {statuses with unread= [name | statuses.unread]}
      , statuses, {read= [] unread= []})

      if (not(external) && noteams && statuses.read == []) then
        #{"{info.mid}-received"} <- modify(info)
      else
        read = if (statuses.read != []) then read(String.concat(", ", statuses.read)) else <></>
        unread = if (statuses.unread != []) then unread(String.concat(", ", statuses.unread)) else <></>
        refresh = if (statuses.unread != []) then refresh(info) else <></>
        #{"{info.mid}-received"} <- WB.List.unstyled([refresh, read, unread])

    /** Fetches status information and push them to the view. */
    @publish @async update(info: ComposeModal.init, _evt): void =
      mid = info.mid
      owners = @toplevel.Message.get_owners(mid)
      (teams, users) = List.partition(Team.key_exists, owners)
      statuses = @toplevel.Message.get_statuses(mid, users)
      statuses =
        List.filter_map(status ->
          if (status.mbox != {inbox} || status.flags.sent) then none
          else
            match (User.get(status.owner)) with
            | {some= user} -> {some= (User.to_full_name(user), status.opened)}
            | _ -> none
            end
        , statuses)
      // No internal recipients but teams: hide the status line.
      if (statuses == []) then Dom.remove(#{"{mid}-status"})
      else set(statuses, teams == [], @toplevel.Message.has_external_owners(mid), info)

  }} // END STATUS

  /** {2} Quick reply. */

  Reply = {{

    // toggle(mid) =
    //   <span title="{AppText.Quick_Reply()}" class="fa fa-reply-o"
    //       rel="tooltip" data-placement="bottom"
    //       onclick={do_toggle(mid, _)}></span>

    @client toggle(mid, _evt: Dom.event) =
      _ = Dom.transition(#{"{mid}-reply"}, Dom.Effect.slide_toggle())
      Dom.give_focus(#{"{mid}-reply-text"})

    @client hide(mid, _evt: Dom.event) =
      _ = Dom.transition(#{"{mid}-reply"}, Dom.Effect.slide_out())
      Dom.give_blur(#{"{mid}-reply-text"})

    @client cancel(mid, _evt) =
      do Button.reset(#{"{mid}-send-reply-button"})
      _ = Dom.transition(#{"{mid}-reply"}, Dom.Effect.slide_out())
      do Dom.set_value(#{"{mid}-reply-text"}, "")
      do AttachedRef.clear("{mid}-quickreply")
      Dom.transform([#{"{mid}-reply-dropzone"} <- <span class="fa fa-chevron-down"/>])

    @client switch_mode(mid, single, all, _) =
      if Dom.has_class(#{"{mid}-reply-switch"}, "fa-reply-all") then
        // Switch to reply all mode.
        do Dom.transform([#{"{mid}-reply-to"} <- all])
        do Dom.remove_class(#{"{mid}-reply-switch"}, "fa-reply-all")
        do Dom.add_class(#{"{mid}-reply-switch"}, "fa-reply-o")
        Dom.set_attribute_unsafe(#{"{mid}-reply-switch"}, "title", "Reply")
      else
        // Switch to simple reply mode.
        do Dom.transform([#{"{mid}-reply-to"} <- single])
        do Dom.remove_class(#{"{mid}-reply-switch"}, "fa-reply-o")
        do Dom.add_class(#{"{mid}-reply-switch"}, "fa-reply-all")
        Dom.set_attribute_unsafe(#{"{mid}-reply-switch"}, "title", "Reply All")

    /** Open upload modal. */
    @client upload(_evt: Dom.event) = Dom.trigger(#up_files, {click})

    /**
     * Server-side callback: if the reply was successfully sent, retrieve the
     * message and insert it at the end of the current thread.
     */
    @private @async @publish callback(mid, res) =
      match (res) with
      | {success= (status, encrypted)} ->
        state = Login.get_state()
        match (MessageController.open_status(state, status, none, {full})) with
        | {success= ~{status header content}} ->
          folders =
            Folder.list_boxes(state.key) |>
            List.filter_map(box -> if Folder.is_system(box.id) then none else some({custom= box.id}), _)
          message = Message.build(state.key, header, status, some(content), false, folders)
          insert(mid, {success= (message, status.owner, encrypted)})
        | ~{failure} ->
          insert(mid, {failure= (failure, [])})
        // Incomplete return value.
        | _ -> insert(mid, {success= (<></>, status.owner, [])})
        end
      | ~{failure} ->
        insert(mid, ~{failure})
      end

    @private @client @async insert(mid, res) =
      match (res) with
      | {success= (_message, user, encrypted)} ->
        // Finish reencryption of file attachments.
        do FileView.Common.reencrypt(user, encrypted)
        // TODO: load reply into current thread.
        // do #thread -<- <li>{message}</li>
        cancel(mid, 0) // Reset quick reply.

      | {failure=(msg, errors)} ->
        do Notifications.error(AppText.Reply_failure(), <>{msg}</>)
        Button.reset(#{"{mid}-send-reply-button"})
        // do Content.clear_modal_errors()
        // do List.iter(id -> Dom.add_class(id, "error"), errors)
      end

    /**
     * @param replyone the recipient in mode Reply.
     * @param replylist the recipients in mode Reply All.
     */
    @client send(mid: Message.id, replyone, replylist, sgn, _evt: Dom.event) =
      do Button.loading(#{"{mid}-send-reply-button"})
      Scheduler.sleep(1000, ->
        all = not(Dom.has_class(#{"{mid}-reply-switch"}, "fa-reply-all"))
        content = Dom.get_value(#{"{mid}-reply-text"})
        to = if all then replylist else [replyone]
        files = List.map(_.id, AttachedRef.list("quickreply"))
        match (MessageController.replyBefore(mid)) with
        | ~{encryption thread from labels subject date key cc security} ->
          oldcontent = Dom.get_text(#{"{mid}-content"}) // Extract content from message view.
          content = "{content}{AppText.print_wrote(date, from, oldcontent, sgn)}"
          if (encryption) then
            // Message encryption is enforced by the chosen security label.
            // First extract the user's secret key.
            UserView.SecretKey.prompt(key, @i18n("Please enter your password to encrypt this message."), secretKey ->
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
                MessageController.Async.reply(mid, thread, to, cc, subject, content, labels, security, files, encryption, callback(mid, _))
              | _ ->
                callback(mid, {failure= (@i18n("Unable to encrypt this message, retry later"), [])})
              end)
          else
            MessageController.Async.reply(mid, thread, to, cc, subject, content, labels, security, files, {none}, callback(mid, _))
        | ~{failure} ->
          callback(mid, ~{failure})
        end
      )

  }} // END REPLY

  // @client @async
  // client_download(urls:list(string)) =
  //   List.iter(url ->
  //     _ = Client.winopen(url, {_blank}, [], false)
  //     void
  //   , urls)

  // @server
  // download_all(mid, mfiles)(_) =
  //   state = Login.get_state()
  //   List.filter_map(hfid ->
  //     match File.get_raw(hfid)
  //     {none} -> none
  //     {some=file} -> some(FSController.to_uri(mid, file))
  //   , mfiles)
  //   |> client_download(_)

  /** {2} Message box selection. */

  /** Call the controller to move the message, and propagate the change to the view. */
  @client move(mid, from, to, _evt: Dom.event) =
    MessageController.Async.move(mid, from, to,
      // Client side.
      | {failure= msg} -> Notifications.error(AppText.Move_failure(), <>{msg}</>)
      | {success= message} ->
        // TODO update box dropdown in message.
        Message.remove(mid, false)
    )

  /**
   * {2} Message deletion.
   *
   * Can be used to delete mails or drafts.
   * NB: the callback function must change the URN to avoid unnecessary messages like 'you are not authorized to read this message'.
   */

  @client delete(mid, isdraft: bool, _evt) =
    if Client.confirm("Are you sure?") then
      MessageController.Async.delete(mid, isdraft,
        // Client side.
        | {failure= msg} -> Notifications.error(AppText.Deletion_failure(), <>{msg}</>)
        | {success= message} ->
          do URN.trim()
          Message.remove(mid, true)   // Remove the message from the view.
      )

  /** Delete all trashed messages. */
  @client empty_trash(_) =
    if Client.confirm("Are you sure?") then
      MessageController.Async.empty_trash(
        // Client side.
        | {failure= msg} -> Notifications.error(AppText.Deletion_failure(), <>{msg}</>)
        | {success= message} ->
          do URN.trim()
          @toplevel.Content.refresh()  // Refresh the view.
      )

  /**
   * Toggle the message information panel. If the panel used to be hidden, this
   * action triggers the update of the message status.
   */
  @client toggle_infos(reedit, _evt: Dom.event) =
    visible = Dom.is_empty(Dom.select_raw_unsafe("#{reedit.mid}-infos:visible"))
    content = Dom.get_text(#{"{reedit.mid}-content"})
    reedit = {reedit with ~content}
    // do if visible && then Status.update(reedit, _evt)
    Dom.transition(#{"{reedit.mid}-infos"}, Dom.Effect.slide_toggle()) |> ignore

  /** Indirectly toggle the message information panel. */
  @client toggle_infos_indirect(mid, _evt) =
    Dom.trigger(#{"{mid}-info-toggle"}, {click})

  /** {2} Toggle star status. */

  @client toggle_star(mid) =
    dom = #{"sb_message_{mid}_star_status"}
    cstar =
      if Dom.has_class(dom, "fa-star") then "fa-star-o"
      else "fa-star"
    do Dom.set_class(dom, "fa {cstar} pull-left clear")
    dom = Dom.select_raw_unsafe("#message_{mid} #star_message")
    Dom.set_class(dom, "fa {cstar}")

  @client star(mid: Message.id, _evt: Dom.event) =
    do toggle_star(mid)
    dom = #{"sb_message_{mid}_star_status"}
    star = Dom.has_class(dom, "fa-star")
    MessageController.Async.star(mid, star,
      // Client side.
      | {failure= msg} -> toggle_star(mid)
      | {success= _} -> void
    )


  /** {2} Toggle read status. */

  /** Toggle the read statuses placed on the message snippet in the list. */
  @client toggle_read(mid) =
    do Misc.toggle("sb_message_{mid}_read_status", "fa-circle-o", "fa-circle")
    Misc.toggle("sb_message_{mid}", "unread", "read")

  @client read(mid: Message.id, _evt: Dom.event) =
    do toggle_read(mid)
    dom = #{"sb_message_{mid}_read_status"}
    unread = Dom.has_class(dom, "fa-circle")
    MessageController.Async.read(mid, not(unread),
      // Client side.
      | {failure= msg} -> toggle_read(mid)
      | {success= mid} -> void
    )

  /** Toggles the read status of the active (selected) message. */
  @client mark_read(evt: Dom.event) =
    dom = Dom.select_raw_unsafe("#messages_list .message.active")
    id = Dom.get_id(dom)
    match Parser.try_parse(sb_message_parser, id) with
    | {some= id} -> read(id, evt)
    | _ -> void
    end

  /** {1} Message construction. */


  /** {2} Content operations. */

  Content = {{

    /**
     * Display the message content. If the message is encrypted, a popup will appear asking to
     * unlock the content. Ultimately, this function should also fold the reply parts.
     * TODO: implement it.
     */
    @both display(content) =
      if (content == "") then
        <pre>{@i18n("(empty message)")}</pre>
      else <pre>{content}</pre>

    /**
     * Open and decrypt the message (optional) content.
     * @param encryption contains the message encryption parameters.
     */
    @client open(user, mid, content, encryption, _evt) =
      match (content) with
      | {some=content} -> decrypt(user, mid, content, encryption)
      | _ -> void
      end

    /** Fetch the message content. */
    @client fetch(user, mid, encryption, _evt) =
      MessageController.Async.open(mid, none, {content},
        | {success= ~{content}} ->
          // Update the status (star + read).
          do Snippet.select(mid) // Change the list selection and update read status.
          decrypt(user, mid, content, encryption)
        | ~{failure} ->
          Notifications.error(@i18n("Load error"), <>{@i18n("Unable to retrieve the message content")}</>)
        | msg ->
          do log("Content.open: unexpected return value: {msg}")
          decrypt(user, mid, "", {none})
      )

    /** Decrypt and insert the message content. */
    @client decrypt(user, mid, content, encryption) =
      match (encryption) with
      | ~{keyNonce messageNonce messagePublicKey messageSecretKey senderPublicKey} ->
        do log("Message.builddecrypt: opening message {mid} for user {user}")
        do log("Message.builddecrypt: messagePublicKey={messagePublicKey}")
        // Accessing public keys.
        messagePublicKey = Uint8Array.decodeBase64(messagePublicKey)
        messageSecretKey = Uint8Array.decodeBase64(messageSecretKey)
        keyNonce = Uint8Array.decodeBase64(keyNonce)
        // Extract the user secret key.
        UserView.SecretKey.prompt(user, @i18n("Please enter your password to decrypt this message."), secretKey ->
          match (secretKey) with
          | {some= secretKey} ->
            // Open the message secret key.
            messageSecretKey = TweetNacl.Box.open(messageSecretKey, keyNonce, messagePublicKey, secretKey)
            match (messageSecretKey) with
            | {some= messageSecretKey} ->
              // Open the message content.
              senderPublicKey = Uint8Array.decodeBase64(senderPublicKey)
              messageNonce = Uint8Array.decodeBase64(messageNonce)
              content = Uint8Array.decodeBase64(content)
              content = TweetNacl.Box.open(content, messageNonce, senderPublicKey, messageSecretKey)
              match (content) with
              | {some= content} ->
                #{"{mid}-content"} <- Uint8Array.encodeUTF8(content) |> display
              | _ -> Notifications.error(AppText.password(), <>{@i18n("PEPS failed to open this message")}</>)
              end
            | _ -> Notifications.error(AppText.password(), <>{@i18n("PEPS failed to open this message")}</>)
            end
          | _ ->
            Notifications.error(AppText.password(), <>{@i18n("PEPS failed to open this message")}</>)
          end)
      | _ -> #{"{mid}-content"} <- display(content)
      end

  }} // END CONTENT


  /** {1} Thread construction. */

  Thread = {{

    /**
     * Select a thread and display it in the #message_viewer.
     * Message loading is asynchronous.
     */

    /** Fetch the message contents, and build the message html. */
    @publish @async fetch(mbox, mid) =
      MessageController.Async.open(mid, mbox, {full},
        | {success= ~{status header content}} ->
          // Server side.
          state = Login.get_state()
          t0 = Date.now()
          html = Thread.build(state.key, header, status, content) |> Xhtml.precompile // Precompile for faster transfer and insertion.
          // 
          do Notification.Broadcast.badges(state.key)
          insert({success= (mbox, header.id, html)})
        | {failure= msg} -> insert({failure= msg})
        | _ -> insert({failure=AppText.Message_not_found()})
      )

    /** Insert the loaded message in the message display. */
    @client insert(res) =
      do Notifications.clear_loading()
      match (res) with
      | {success= (mbox, mid, html)} ->
        do #message_viewer <- html
        do Option.iter(box -> URN.change(URN.make({messages= box}, ["{mid}"])), mbox)
        Snippet.select(mid)
      | {failure= msg} ->
        #message_viewer <- @toplevel.Content.not_allowed_message

    /**
     * If the message id is defined (the urn path gives a message id), send a request for the message information.
     * The messgae is loaded by the callback, {finish_message}.
     */
    @client load(mbox, mid, thread, _evt) =
      match (mid) with
      | {some= mid} ->
        cthread = Dom.get_attribute(#thread, "data-thread")
        // This thread has already been loaded.
        // TODO: load new messages.
        if (cthread == thread && Option.is_some(thread)) then
          do Thread.goto(mid, false) // Scroll to message in thread.
          do Option.iter(box -> URN.change(URN.make({messages= box}, ["{mid}"])), mbox) // Update URN.
          Dom.trigger(#{"{mid}-content-toggle"}, {click}) // Open the content.
        else fetch(mbox, mid)
      | _ -> #message_viewer <- <></>
      end

    /**
     * Scroll the thread list down to the given message.
     * @param fast How fast the scrolling should be.
     */
    @client goto(mid: string, fast: bool) =
      // Get position of message.
      message = #{"message_{mid}"}
      thread = #message_viewer
      top = Dom.get_offset(message).y_px - Dom.get_offset(thread).y_px // Ignores message_viewer since its position is fixed.
      scroll = Dom.get_scroll_top(thread)
      // Scroll the message to the top of the thread.
      if fast then Dom.set_scroll_top(thread, scroll+top)
      else Dom.transition(thread, Dom.Effect.scroll_to_xy(none, some(scroll+top))) |> ignore

    /**
     * Build a thread.
     *
     * Thread construction follows the rules:
     *  - if the thread contains only one message, then build_thread returns the result of build message.
     *  - if the thread contains more than one message, load the one or two messages before and after.
     *    Messages are placed in a list.
     * Messages are fetched without regard to the box.
     */
    @server_private
    build(key: User.key, header, status, content) =
      folders =
        Folder.list_boxes(key) |>
        List.filter_map(box -> if Folder.is_system(box.id) then none else some({custom= box.id}), _)
      mid = header.id
      t0 = Date.now()
      messages = MessageController.get_messages_of_thread(key, header.thread)
      t1 = Date.now()
      (thread, _) = List.fold(message, (list, first) ->
        if (message.header.id == mid)
        then (list <+> Message.build(key, header, status, some(content), first, folders), false)
        else (list <+> Message.build(key, message.header, message.status, none, first, folders), false)
      , messages, (<></>, true))
      thread = <ul id="thread" data-thread="{header.thread}" class="list-unstyled" onready={_ -> Thread.goto(mid, true)}>{thread}</ul>
      t2 = Date.now()

      do log("Thread.build ; building thread {header.thread}")
      do log("Thread.build ; fetching messages ... {Utils.delta(t0, t1)}ms")
      do log("Thread.build ; building ............ {Utils.delta(t1, t2)}ms ({List.length(messages)})")

      thread

  }} // END THREAD


  /** {1} Single messages. */

  Message = {{

    /**
     * Remove a message from the viewer and the list of messages.
     * Called when messages are either deleted or moved (in case the message is deleted, it is also removed
     * from the current thread).
     */
    @client remove(mid, deleted: bool) =
      do Dom.remove(#{"sb_message_{mid}"})    // Remove message snippet from side list.
      if (deleted) then                       // Remove message from current thread.
        Dom.remove(#{"message_{mid}"})

    /**
     * Fetch a single message from the database. If the thread id matches that of the snippet,
     * the message is also built and inserted in the current thread.
     */
    @publish fetch(mid, thread) =
      MessageController.Async.open(mid, none, {header},
        | {success= ~{header status}} ->
          snippet = Snippet.build(none, @toplevel.Message.snippet(status))
          message =
            if (some(header.thread) == thread) then
              state = Login.get_state()
              folders =
                Folder.list_boxes(state.key) |>
                List.filter_map(box -> if Folder.is_system(box.id) then none else some({custom= box.id}), _)
              Message.build(state.key, header, status, none, false, folders)
            else <></>
          insert(thread, status.mbox, snippet, message)
        | ~{failure} -> void
        | msg -> void
      )

    @client insert(thread, mbox, snippet, message) =
      cthread = Dom.get_attribute(#thread, "data-thread")
      // Check that neither the mode nor the thread changed in the mean.
      do if (URN.get().mode == {messages= mbox}) then
        #messages_list_items -<- snippet
      if (cthread == thread) then #thread +<- message

    /**
     * Load and insert a message at the beginning of the message list (and in the opened thread
     * if the thread id matches). This method handles {received} notifications.
     */
    @client load(mid) =
      thread = Dom.get_attribute(#thread, "data-thread")
      fetch(mid, thread)

    /**
     * Build the message display. Keep server side, else all i18n calls amount to ~20 requests being sent to the server.
     * @content the message content (overrides message.content). If none, the content remains hidden until the the toggle
     *  has been hit (useful for threads).
     *
     * @param key active user
     * @param displayHeading hide subject and classification.
     */
    @server_private
    build(key: User.key, header, status, content, displayHeading:bool, folders) =
      t0 = Date.now()
      // Extract encryption parameters.
      encryption =
        match (header.encryption, status.encryption) with
        | ( {key= messagePublicKey nonce= messageNonce},
            {key= messageSecretKey nonce= keyNonce} ) ->
          senderPublicKey = User.publicKey(header.creator)
          ~{messagePublicKey messageSecretKey messageNonce keyNonce senderPublicKey}
        | _ -> {none}
        end

      mid = header.id
      labels = Label.to_client_list(header.labels ++ status.labels)
      files = get_files(header.id, header.files)
      replyto = @toplevel.Message.make_reply_list(key, status.mbox, header)
      classification = Label.to_client(header.security) |> LabelView.make_label(_, none)
      signature = User.get_signature(key)
      from = @toplevel.Message.Address.to_html(header.from, none, true)

      // Flags.
      is_draft = status.mbox == {draft}
      is_sent = status.flags.sent   // Not the 'sent' box, but identifies the active user as the message SENDER.
      is_trash = status.mbox == {trash}

      t1 = Date.now()

      /// Message header.
      subject = if header.subject == "" then "({@i18n("no subject")})" else header.subject
      heading =
        if (displayHeading) then
          <div class="pane-heading" style="position:relative;">
            <div class="pane-heading-label">{classification}</div>
            <h3>{subject}</h3>
          </div>
        else <></>

      /// Profile picture of the message sender.
      thumbnail = userimg(key, header.from)
      picture =
        match (thumbnail) with
          | {some= picture} -> <img src={Utils.dataUrl(picture)} class="user-img"/>
          | _ -> <div class="user-img user-img-default"></div>
        end

      /// Message information panel.
      // Contents: labels (shared + personal), receivers, sender, date.
      labelsline =
        dropdown = Labels.dropdown(mid, key)
        clabels = Labels.line(mid, key, labels)

        <div class="msg-item">
          <label>{AppText.labels()}:</label>
          <span class="dropdown">
            <a data-toggle="dropdown" class="fa fa-plus-circle-o dropdown-toggle"></a>
            {dropdown}
          </span>
          <span id="{mid}-labels-list">{clabels}</span>
        </div>
        // onclick={_evt -> Misc.reposition("label-add", "label-dropdown")}

      fulldate =
        <div class="msg-item" id="{mid}-fulldate">
          <label>{AppText.Date()}:</label>
        </div>

      info =
        <span id="{mid}-info-toggle" data-placement="bottom" rel="tooltip"
            title="View details" class="fa fa-chevron-down"></span>
      messageinfo =
        from = @toplevel.Message.Address.to_html(header.from, none, false)
        to = addresses_list(mid, header.to, none, false)
        cc = addresses_list(mid, header.cc, none, false)
        bcc = addresses_list(mid, header.bcc, none, false)
        <div id="{mid}-infos" class="message_infos msg-row" style="display:none">
          <div class="msg-item"><label>{AppText.From()}:</label> {from}</div>
          <div class="msg-item"><label>{AppText.To()}:</label> {to}</div>
          { if header.cc == [] then <></>
            else <div class="msg-item"><label>{AppText.Cc()}:</label> {cc}</div> }
          { if header.bcc == [] then <></>
            else <div class="msg-item"><label>{AppText.Bcc()}:</label> {bcc}</div> }
          {fulldate}
          {labelsline}
        </div>

      t2 = Date.now()

      /// Message header.
      // Contents: sender, status line.
      date =
        id = Dom.fresh_id()
        <span id={id} onready={Misc.insert_date(id, header.created, "%d/%m/%y - %H:%M")} class="message_date"></span>
      attachments =
        nbatch = List.length(files)
        if nbatch > 0 then
          s = if nbatch > 1 then AppText.attachments() else AppText.attachment()
          <span id="{mid}-attachments" title="{nbatch} {s}" class="fa fa-paperclip" data-placement="bottom" rel="tooltip"></span>
        else <></>
      // Statuses of mail receivers (only for internally sent mails).
      statuses =
        if not(is_sent) then <></>
        else
          <div id="{mid}-status" class="msg-status msg-item">
            <label>{AppText.status()}: </label>
            <span id="{mid}-received"></span>
          </div>
      action =
        if is_sent || is_draft then <></>
        else
          <span title="{AppText.Quick_Reply()}" class="fa fa-reply-o" data-placement="bottom" rel="tooltip"
              onclick={Reply.toggle(mid, _)}></span>
      cstar = if (status.flags.starred) then "fa-star" else "fa-star-o"
      star = <span id=#star_message class="fa {cstar}" onclick={star(mid, _)}></span>
      messageheader =
        to = addresses_list(mid, header.to, some(2), true)
          <div class="pull-left">
            {picture}
            <span class="message_from">{from}</span>
            <span class="prepend_to">{AppText.To()} </span>
            <span class="message_to">{to}</span>
            {info}
          </div>
      messagedate =
        <div class="pull-right msg-item">
            {attachments}
            {action}
            {date}
            {star}
          </div>

      t3 = Date.now()

      /// Quick reply.
      // Contents: a minimal reply editor.
      replylist =
        List.map(@toplevel.Message.Address.to_html(_, none, true), replyto) |>
        List.intersperse(<>, </>, _) |>
        List.fold(`<+>`, _, <></>)
      replymode =
        if List.length(replyto) > 1 then
          // NB: would add rel=tooltip, but the tooltip is not updated after title change.
          <span id="{mid}-reply-switch"
              class="fa fa-reply-all" title="Reply All" data-placement="bottom"
              onclick={@public_env(Reply.switch_mode(mid, from, replylist, _))}>
          </span>
        else <></>
      quickreply =
        openreply = <a id="{mid}-expand-reply">{@i18n("Expand")}</a>
        cancelbtn = <a onclick={Reply.cancel(mid, _)}>{@i18n("Close")}</a>
        sendbtn =
          <button type="button" class="btn btn-primary" id="{mid}-send-reply-button"
              data-complete-text="{AppText.Send()}"
              data-loading-text="{AppText.Sending()}">
            {AppText.Send()}
          </button>
        // Build reply panel.
        <div id="{mid}-reply" class="message message-reply">
          <div class="msg-row">
            <div class="pull-right message-close">{openreply}{cancelbtn}</div>
            <div class="message-reply-to pull-left">
              <label>{@i18n("Reply to")}: </label>
              <span id="{mid}-reply-to">{from}</span>
              {replymode}
            </div>
          </div>
          <div class="msg-row">
            <div class="pull-right message-reply-actions">
              <span id="quickreply-dropzone" class="btn btn-icon fa fa-paperclip dropzone"
                  onclick={Reply.upload} rel="tooltip"
                  title="{@i18n("Drop files here")}" data-placement="left">
                <img id="{mid}-reply-file-loader" src="/resources/img/facebook-loader.gif" style="display:none"/>
              </span>
              {sendbtn}
            </div>
            <div class="message-reply-field"><textarea id="{mid}-reply-text" onkeyesc={Reply.hide(mid, _)} row="8">
              </textarea>
            </div>
          </div>
        </div>

      t4 = Date.now()

      /// Full message.
      // Contents: the previously built parts, plus the content and missing headers.
      actions =
        if is_draft then
          delete =
            <button type="button"
                class="btn btn-icon" rel="tooltip"
                title="{AppText.delete()}" data-placement="bottom"
                onclick={MessageView.delete(mid, is_draft, _)}>
              <i class="fa fa-trash-o"/>
            </button>
          edit =
            <button id="{mid}-edit" type="button"
                class="btn btn-icon" rel="tooltip"
                title="{AppText.Edit()}" data-placement="bottom">
              <i class="fa fa-pencil-square-o"/>
            </button>
          // Available actions: edit + delete.
          <div class="message_actions">{edit}{delete}</div>
        else
          // Move action.
          menu =
            boxes = Box.available ++ folders
            options =
              List.map(mbox ->
                if mbox == status.mbox then { active=<>{Box.name(mbox)}</> href=none onclick=ignore }
                else                        { inactive=<>{Box.name(mbox)}</> href=none onclick=move(mid, status.mbox, mbox, _) }
              , boxes)
            // Show untrash action if message is in trash.
            actions =
              if is_trash then [
                { divider },
                { inactive= <>{@i18n("Untrash")}</>
                  href=none
                  onclick=move(mid, {trash}, status.moved.from, _) }
              ] else []
            @toplevel.List.map(WB.Navigation.nav_elt_to_xhtml(false, identity), options ++ actions)
          move =
            <div class="btn-group">
              <button type="button"
                  class="btn btn-icon fa fa-share-o dropdown-toggle"
                  data-toggle="dropdown">
              </button>
              <ul class="dropdown-menu pull-right" role="menu">
                <li class="dropdown-header">{@i18n("Move To")}</li>
                {menu}
              </ul>
            </div>
          reply =
            <button type="button" id="{mid}-replyone"
                class="btn btn-icon fa fa-reply-o" rel="tooltip"
                title="{AppText.Reply()}" data-placement="left">
            </button>
          reply_all =
            if List.length(replyto) <= 1 then <></>
            else
              <button type="button" id="{mid}-replyall"
                  class="btn btn-icon fa fa-reply-all" rel="tooltip"
                  title="{AppText.Reply_All()}" data-placement="left">
              </button>
          forward =
            <button type="button" id="{mid}-forward"
                class="btn btn-icon fa fa-arrow-right" rel="tooltip"
                title="{AppText.Forward()}" data-placement="left">
            </button>
          delete =
            <button type="button"
                class="btn btn-icon fa fa-trash-o" rel="tooltip"
                title="{AppText.delete()}" data-placement="left"
                onclick={MessageView.delete(mid, is_draft, _)}>
            </button>

          if is_trash then <div class="message_actions">{reply <+> reply_all <+> forward <+> delete <+> move}</div>
          else             <div class="message_actions">{reply <+> reply_all <+> forward <+> move}</div>

      content =
        if (content == none) then
          <div id="{mid}-content" class="message_content">
            <a id="{mid}-content-toggle" onclick={Content.fetch(key, mid, encryption, _)}><small>{@i18n("Display content")}</small></a>
          </div>
        else if (encryption == {none}) then <div id="{mid}-content" class="message_content">{Content.display(content ? "")}</div>
        else <div id="{mid}-content" class="message_content" onready={Content.open(key, mid, content, encryption, _)}></div>
      // Assemble all elements.
      message =
        <li id="message_{mid}" onready={Message.initialize(header, is_sent, labels, replyto, signature, _)}>
          {heading}
          <div class="message">
            <div class="msg-heading msg-row">
              {actions}
              {messageheader}
            </div>
            <div class="msg-summary">
              <div class="msg-row">
                {messagedate}
                {statuses}
              </div>
              {messageinfo}
            </div>
            <div class="message_atts">
              { if files == [] then <></>
                else
                  <div class="files-attached"><h6>{AppText.Attachments()}</h6>{build_attachments(files)}</div> }
            </div>
            {content}
          </div>
          {quickreply}
        </li>

      t5 = Date.now()


      message

    /**
     * Bind all event handlers to a message. Should be called as soon as the html has been inserted.
     * Useful because most handlers share the same closure, when the compiler is unable to share it.
     */
    @client initialize(header, sent, labels, replyto, signature, _evt) =
      mid = header.id
      created = header.created
      from = header.from
      modifysecurity = false
      init = ~{
        ComposeView.defaults with
        mid thread=some(header.thread) to=header.to cc=header.cc bcc=header.bcc
        content="" security=header.security
        subject=header.subject
        files=header.files labels=labels
      }
      do if (sent) then Status.update(init, _evt)
      do #{"{mid}-fulldate"} +<- Misc.date(created, true, Date.default_printer)
      do Dom.bind(#{"{mid}-attachments"}, {click}, toggle_infos(init, _)) |> ignore
      do Dom.bind(#{"{mid}-info-toggle"}, {click}, toggle_infos(init, _)) |> ignore
      do Dom.bind(#{"{mid}-expand-reply"}, {click}, ComposeView.open_reply(init, from, created, replyto, modifysecurity, signature, _)) |> ignore
      do Dom.bind(#{"{mid}-replyone"}, {click}, ComposeView.reply(init, from, created, replyto, false, modifysecurity, signature, _)) |> ignore
      do Dom.bind(#{"{mid}-replyall"}, {click}, ComposeView.reply(init, from, created, replyto, true, modifysecurity, signature, _)) |> ignore
      do Dom.bind(#{"{mid}-forward"}, {click}, ComposeView.forward(init, modifysecurity, signature, _)) |> ignore
      do Dom.bind(#{"{mid}-edit"}, {click}, (_ -> ComposeView.edit(init))) |> ignore
      Dom.bind(#{"{mid}-send-reply-button"}, {click}, Reply.send(mid, from, replyto, signature, _)) |> ignore

  }} // END MESSAGE

  /**
   * {1} Message list display.
   *
   * Because the difficulty, inherent to the classification system, of determining the number of messages
   * that we will be able to show to a user after a fetch, it is easier to load the messages in an infinite
   * scroll. Then, messages fetches are triggered when the user reaches a certain point in the scroll, and
   * treated asynchronously so as not to disrupt the flow of the scroll.
   *
   * Two loading functions are available:
   *   - {server_page} fetches a list of messages, and display them in a list under a header.
   *    This function must be called at page refreshes to set up the list layout.
   *
   *   - server_messages fetches and formats message snippets and return them as list element, ready to be
   *    inserted in the message list.
   */

  Snippet = {{

    /**
     * Fetch pre-formatted message snippets from the database, ready for
     * insertion in the view. The asynchronous status ensures that the list scroll
     * remains fluid.
     */
    @publish @async
    fetch(box, ref: Date.date, filter, callback) =
      state = Login.get_state()
      if not(Login.is_logged(state)) then callback(<></>, ref, 0)
      else
        t0 = Date.now()
        page = MessageController.get_messages_of_box(state.key, box, ref, filter)


        pagehtml = build_list({some=box}, page) |> Xhtml.precompile
        callback(pagehtml, page.last, page.size)

    /**
     * Insert the loaded elements into the view.
     * If more messages are to be expected, then restore the {scroll} handler, with updated
     * parameters (set to fetch the following messages).
     */
    @client insert(box, filter, html, ref, size) =
      do #messages_list_items +<- html                              // Append new messages to the end of the list.
      if (size > 0) then
        Dom.bind(#messages_list_items, {scroll}, scroll(box, ref, filter, _)) |> ignore

    /**
     * Load more messages, and append them to the end of the list.
     * Called exclusively by the function {scroll}, which detects the optimal moment for loading more messages.
     * This function must NOT be async: we need to deactivate the {scroll} event handler, to avoid duplicate
     * calls to {server_messages}. {server_messages} IS asynchronous, and this ensures the fluidity of the scroll.
     */
    @client load(box, ref: Date.date, filter): void =
      do debug("load_more: in:{box} ; from:{ref}")
      do Dom.unbind_event(#messages_list_items, {scroll})           // Unbind event to avoid multiple requests.
      fetch(box, ref, filter, insert(box, filter, _, _, _))         // Send request for more elements.

    /**
     * Called on scroll events. Detect when less than a certain amount of messages remain in the list
     * to know when to trigger the function to fetch more messages.
     * Message height is estomated at 80px ofr the purpose of determining the number of messages left in the list.
     * When less than three times the amount of visible messages remain in the list, new messages are fetched.
     * Same as {load_more}, this function needn't be asynchronous.
     */
    @client scroll(box, ref, filter, _evt): void =
      full = Dom.get_scrollable_size(#messages_list_items).y_px
      current = Dom.get_scroll_top(#messages_list_items)
      height = Dom.get_height(#messages_list_items)
      mvisible = height/80
      mleft = (full-current)/80 - mvisible  // Number of messages left in the list to scroll for.
      if (mleft < 3*mvisible) then load(box, ref, filter)

    /** Change the message selection in the side list. */
    @client select(mid: Message.id) =
      do Dom.remove_class(Dom.select_raw_unsafe("#messages_list .message"), "active")
      do Dom.add_class(#{"sb_message_{mid}"}, "active")
      do Dom.remove_class(#{"sb_message_{mid}_read_status"}, "fa-circle")
      do Dom.add_class(#{"sb_message_{mid}_read_status"}, "fa-circle-o")
      do Dom.remove_class(#{"sb_message_{mid}"}, "unread")
      Dom.add_class(#{"sb_message_{mid}"}, "read")

    /** Select and open a message from the message list. */
    @client @private selectby(selector) =
      sel =
        Dom.select_raw_unsafe("#messages_list_items .message.active") |>
        Dom.select_parent_one |> selector |>
        Dom.select_children
      match Parser.try_parse(sb_message_parser, Dom.get_id(sel))
      | {some= id} -> Dom.trigger(sel, {click})
      | _ -> void
      end

    /** Select the next or previous message in the list. */
    @client prev(_evt: Dom.event) = selectby(Dom.select_previous_one)
    @client next(_evt: Dom.event) = selectby(Dom.select_next_one)

    /** Formats a message snippet. */
    @server_private build(mbox, message: Message.snippet) =
      highlight(opt, def, emptystr, limit) =
        Option.lazy_switch(Xhtml.of_string_unsafe, ->
          if def == "" then <>({emptystr})</>
          else <>{Utils.string_limit(limit, def)}</>, opt)
      // Misc.
      mid = message.id
      thread = message.thread
      subject = highlight(message.highlighted.subject, message.subject, @i18n("no subject"), 32)
      content = highlight(message.highlighted.content, message.snippet, @i18n("empty message"), 100)
      rclass = if message.flags.read then "read" else "unread"
      incopy = if message.flags.incopy then "incopy" else ""
      // subject = if msubject == <></> then <>{"({@i18n("no subject")})"}</> else msubject
      // content = if mcontent == <></> then <>{"({@i18n("empty message")})"}</> else mcontent
      security =
        WB.Label.make(<></>, Label.to_importance(Label.category(message.security))) |>
        Xhtml.update_class("pull-right", _)
      date =
        id = Dom.fresh_id()
        <a id={id} onready={Misc.insert_timer(id, message.created)} class="message_date pull-right"></a>
      // Message sender.
      from =
        if message.flags.sent then
          email =
            match (@toplevel.Message.Address.email(message.from)) with
            | {some= email} -> {external= {email with name=some(@i18n("me"))}}
            | _ -> {unspecified=@i18n("me")}
            end
          me = @toplevel.Message.Address.to_html(email, none, true)
          <span class="message_to">{me}</span>
        else
          from = @toplevel.Message.Address.to_html(message.from, some(24), true)
          <span class="message_from">{from}</span>
      // Attachment paperclip.
      attach =
        nfiles = List.length(message.files)
        if nfiles > 0 then
          <span title="{@i18n("This message has {nfiles} attachments")}" class="fa fa-paperclip" data-placement="bottom" rel="tooltip"></span>
        else <></>
      // Attachment highlightings.
      files = List.map(extract -> <div class="file_content">{Xhtml.of_string_unsafe(extract)}</div>, message.highlighted.files)
      // Flags.
      qactions =
        cread = if message.flags.read then "fa-circle-o" else "fa-circle"
        cstar = if message.flags.starred then "fa-star" else "fa-star-o"
        icon_size = "fa"
        <span id="sb_message_{mid}_star_status" class="{icon_size} {cstar} pull-left clear"
            onclick={star(mid, _)}
            options:onclick={[{stop_propagation}]}></span>
        <span id="sb_message_{mid}_read_status" class="{icon_size} {cread} pull-left clear"
            onclick={read(mid, _)}
            options:onclick={[{stop_propagation}]}></span>
      // Build snippet.
      <div id="sb_message_{mid}" class="message {incopy} {rclass}" onclick={Thread.load(mbox, some(mid), some(thread), _)}>
        {date}
        <div class="message_qactions pull-left">{qactions}</div>
        <div class="message_owners">
          {from}{attach}
        </div>
        <div class="message_subj">
          {security}
          <span>{subject}</span>
        </div>
        <div class="message_content">{content}</div>
        {files}
      </div>

    /** Build the list of message snippets. */
    @server_private build_list(mbox, page) =
      t0 = Date.now()
      list = List.rev_map(message -> <li>{build(mbox, message)}</li>, page.elts)


      List.fold(`<+>`, list, <></>)

  }} // END SNIPPET


  /**
   * {1} Panel construction.
   *
   * Build the snippet list frame, filled with the first snippets, and insert it
   * in the view.
   */

  Panel = {{
    /** Build the message panel, filled with the first messages in the box. */
    @publish @async
    fetch(box, ref: Date.date, filter, callback) =
      state = Login.get_state()
      if not(Login.is_logged(state)) then callback(Xhtml.precompile(<>{AppText.login_please()}</>))
      else
        t0 = Date.now()
        page = MessageController.get_messages_of_box(state.key, box, ref, filter)


        build(state, {some=box}, page, none, filter) |> Xhtml.precompile |> callback

    /**
     * Initialize the message list by inserting the list header.
     * This function is called once to build the page layout.
     */
    @client insert(html) = #messages_list <- html
    @client load(box, filter, _evt) = fetch(box, Date.now(), filter, insert)

    /** Build the full panel containg the list of messages */
    @server_private build(state:Login.state, mbox, page:Message.page, query, filter) =
      // Empty list.
      if page.size <= 0 then
        <div class="pane-heading">
          <h3>{Box.name(mbox ? {inbox})}</h3>
        </div>
        <div class="empty-text">
          <p>{@i18n("No thread")}</p>
        </div>
      else
        elts = Snippet.build_list(mbox, page)
        match query with
        // Query results.
        | {some=query} ->
          mid = List.head(page.elts).id // List is not empty.
          header =
            <div class="pane-heading" onready={Thread.load(mbox, some(mid), none, _)}>
              <h3>
                {AppText.search()}: <small class="page_num">{page.size} {@i18n("results for")} <b>{query}</b></small>
              </h3>
            </div>
          header <+> <ul class="list-unstyled">{elts}</ul>
        // Normal fetch.
        | {none} ->
          t0 = Date.now()
          mbox = mbox ? {inbox}
          ref = page.last
          mailcount = Folder.count(state.key, mbox)
          mailcount =
            if (mailcount > 1) then <small class="page_num">{@i18n("about {mailcount} results")}</small>
            else <></>
          empty_trash =
            if (mbox == {trash}) then <a onclick={empty_trash}>{AppText.empty_trash()}</a>
            else <></>
          boxname = Box.name(mbox)
          header =
            <div class="pane-heading">
              <span class="pull-right">{empty_trash}</span>
              <h3>
                {boxname} {mailcount}
              </h3>
            </div>
          html = header <+> <ul id="messages_list_items" class="list-unstyled" onscroll={Snippet.scroll(mbox, ref, filter, _)}>{elts}</ul>


          html
        end

  }} // END PANEL


  /**
   * {1} Putting it together.
   *
   * Build the html for a mail box.
   * The html is composed of two parts:
   *   - the side pane with the message list.
   *   - the open message.
   * The open message's id is given by the path, which should be of the form: {mbox}/{mid}.
   * @result the Xhtml serialization of the html page.
   */
  @server_private
  build_box(state:Login.state, mbox:Mail.box, path:Path.t, filter) =
    key = state.key
    if not(Login.is_logged(state)) then @toplevel.Content.login_please
    else
      do debug("Building box {mbox} for key:{key} path:{path}")
      mid = match (path) with [mid | _] -> some(@toplevel.Message.midofs(mid)) | default -> none end
      <div id=#messages_list class="messages_list pane-left" onready={Panel.load(mbox, filter, _)}></div>
      <div id=#message_viewer class="message_viewer pane-right" onready={Thread.load(some(mbox), mid, none, _)}></div>


  @server_private
  inbox(state, path) = build_box(state, {inbox}, path, none)
  @server_private
  starred(state, path) = build_box(state, {starred}, path, none)
  @server_private
  archive(state, path) = build_box(state, {archive}, path, none)
  @server_private
  draft(state, path) = build_box(state, {draft}, path, none)
  @server_private
  sent(state, path) = build_box(state, {sent}, path, none)
  @server_private
  trash(state, path) = build_box(state, {trash}, path, none)
  @server_private
  folder(state, name, path) =
    id = Folder.find(state.key, name) ? Folder.idofs("")
    build_box(state, {custom= id}, path, none)

  /** Creation of the sidebar. */
  Sidebar: Sidebar.sign = {{

    build(state, options, mode) =
      add_folder =
        <a class="pull-right fa fa-plus-circle-o"
          title="{AppText.create_new_folder()}" rel="tooltip" data-placement="left"
          onclick={FolderView.do_create}/>

      onclick(box) = @toplevel.Content.update_callback({mode= {messages= box} path= []}, _)
      sgn = User.get_signature(state.key)
      [
        { id=SidebarView.action_id text=AppText.compose() action=ComposeView.new(sgn, _) },
        { id="INBOX"    name="INBOX"    icon="inbox-o"      title = AppText.inbox()    onclick = onclick({inbox}) },
        { id="STARRED"  name="STARRED"  icon="star"         title = AppText.starred()  onclick = onclick({starred}) },
        { id="DRAFT"    name="DRAFT"    icon="file-text-o"  title = AppText.drafts()   onclick = onclick({draft}) },
        { id="SENT"     name="SENT"     icon="send-o"       title = AppText.sent()     onclick = onclick({sent}) },
        { id="ARCHIVE"  name="ARCHIVE"  icon="archive-o"    title = AppText.archive()  onclick = onclick({archive}) },
        { id="TRASH"    name="TRASH"    icon="trash-o"      title = AppText.trash()    onclick = onclick({trash}) },
        { separator=AppText.folders() button=some(add_folder) },
        { content=FolderView.build_list(state, options.view) }
      ]

  }} // END SIDEBAR


}}
