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


package com.mlstate.webmail.controller

/** Type of the result of a page query. */
type Message.page = {
  first: Date.date
  last: Date.date
  elts: list(Message.snippet)
  more: bool
  size: int
}

MessageController = {{

  /** {1} Utils. */

  log = Log.notice("[MessageController]", _)
  warning = Log.warning("[MessageController]", _)
  debug = Log.debug("[MessageController]", _)
  error = Log.error("[MessageController]", _)


  /** Parse a user address. */
  @publish identify(addr: string) =
    state = Login.get_state()
    if (not(Login.is_logged(state))) then {unspecified=addr}
    else Message.Address.of_string(addr)

  /** {1} Query. */

  /**
   * More complicated: get the messages of one specific page. Since this is not possible
   * to express security checks as db queries, the result of the request may not be what
   * is expected, and may have to be rectified (using more requests).
   * For pages other than the first, the date of the last message pf the page before is needed
   * as an absolute reference of the start of the page (skip can not be relied upon).
   *
   * Note that unreadable messages are already filtered out while in the model.
   *
   * @param ref reference date.
   * @param filter an optional custom filter.
   *
   * @return a messages page
   */
  @server_private
  get_messages_of_box(key: User.key, box: Mail.box, ref: Date.date, filter): Message.page =
    pagesize = AppConfig.pagesize
    t0 = Date.now()
    page =
      match (filter) with
      | {some= filter} ->
        more = Message.ranged_in_mbox(key, box, _, _)
        DbUtils.get_page(ref, pagesize, filter, _.created, more)
      // No need to go through the generic page get since the results returned from the db
      // are exact.
      | _ ->
        messages = Message.ranged_in_mbox(key, box, ref, pagesize) |> Iter.to_list
        first = Option.map(_.created, List.head_opt(messages)) ? ref
        last = Option.map(_.created, Utils.last_opt(messages)) ? ref
        ~{first last elts=messages more=true size=List.length(messages)}
      end
    t1 = Date.now()
    page = { first= page.first last= page.last
      elts= List.map(Message.snippet, page.elts)
      more= page.more size= page.size }


    page

  /**
   * Return messages that are part of the current thread, boath after and before the current
   * message. Message boxes do not matter, except for the deleted messages.
   */
  @server_private
  get_messages_of_thread(key: User.key, thread: Thread.id) =
    Message.all_in_thread(key, thread)

  /**
   * Retrieve messages with the given label.
   * Caution: can only applied to personal labels, and maybe shared ones in the future.
   */
  @server_private
  get_messages_of_label(key:User.key, label:Label.id) =
    Message.all_with_label(key, label) |> Iter.map(Message.snippet, _) |> Iter.to_list

  /** {1} Message writes. */

  /** Filter out the contacts who blocked the active user. */
  @package remove_blocking(from, owners) =
    match (from) with
    | {some= from} -> List.filter(owner -> not(Contact.blocked(owner, from.address)), owners)
    | _ -> owners
    end

  /** Unlock messages. */
  @publish unlock(mid: Message.id) =
    state = Login.get_state()
    if (not(Login.is_logged(state))) then void
    else Message.unlock(state.key, mid)

  /**
   * @param message needn't be of type Message.header. Only the fields 'owners' and 'creator' are
   *    needed to check the property.
   */
  @server_private user_can_read_message(key: User.key, message) =
    key == message.creator ||
    Label.KeySem.user_can_read_security(key, message.security)

  /** Check that the recipients have the clearance to read the attachments. */
  @private check_files(message, to) =
    error = List.fold(fid, acc ->
      match File.get_security(fid) with
      | {some= security} ->
        List.fold(user, acc ->
          canread = Label.KeySem.user_can_read_security(user, security)
          if not(canread) then
            [user|acc]
          else acc
        , to, acc)
      | _ -> acc
      end
    , message.files, [])
    // Report potential errors.
    match (error) with
    | [] -> {success}
    | _ ->
      emails = List.filter_map(User.get_email, error) |> List.map(Email.to_name, _)
      {failure= @i18n("The following users can't read some of the attached files: {String.concat(",", emails)}")}
    end

  /** Certify that all recipients can read the message as well as all file attachments. */
  check_message(message, to) =
    users = List.filter(key -> not(user_can_read_message(key, message)), to)
    match users with
    | [] -> check_files(message, to)
    | _ ->
      // FIXME: Still print users whose email can not be recovered ?
      emails = List.filter_map(User.get_email, users) |> List.map(Email.to_name, _)
      {failure= @i18n("The following users don't have the level to receive your mail: {String.concat(",", emails)}")}
    end

  /**
   * Generic function to send mails or replies, save drafts...
   * TODO: add error statuses to the adequate dom elements (recipient input or security class).
   *
   * @param mid id of the message, in case of (re)edition.
   * @param thread id of the thread.
   * @param action the action performed: send or draft.
   * @param encryption encryption message encryption. {encryption} is none if encryption is not active,
   *      or a record with field nonce, publicKey, secretKey else.
   */
  @private
  write(key, mid, thread, from, to, cc, bcc, subject, labels, security, content, files, action, is_reedit, encryption) =
    // Sort addresses.
    incopy = cc ++ bcc
    addrs = Message.Address.categorize(to ++ incopy)
    incopy = Message.Address.keys(incopy)
    external = addrs.external != []
    // Internet compatibility.
    internet = Option.map(_.category, Label.get(security)) == {some= {unprotected= true}}

    // Check for unparsed addresses.
    if action == {send} && addrs.unspecified != [] then
      {failure=(@i18n("The following addresses could not be parsed: {String.concat(",", addrs.unspecified)}"), [])}
    // Checks recipients.
    else if action == {send} && addrs.external == [] && addrs.users == [] && addrs.teams == [] then
      {failure=(@i18n("No recipient specified"), [])}
    // Check whether user can user specified class.
    else if (not(Label.KeySem.user_can_use_label(key, security))) then
      {failure=(@i18n("you do not have access to this security class"), [])}
    // Check security label for internet.
    else if action == {send} && external && not(internet) && AppConfig.has_security_labels then
      {failure=(@i18n("Please use an internet compatible label"), [])}
    else
      // Separate labels into shared and personal.
      slabels = Label.categorize(Utils.const(true), labels)
      personal = List.map(_.id, slabels.personal)
      shared = List.map(_.id, slabels.shared)
      // Build message.
      snippetcontent = if (encryption != {none}) then @i18n("No snippet available") else content
      header = ~{ Message.make(key, mid, from, to, cc, bcc, subject, none, snippetcontent) with
        external thread= thread ? mid
        labels = shared security
        files = files
      }
      // List receivers (sender excluded).
      receivers =
        if action == {draft} then []
        else remove_blocking(Message.Address.email(from), addrs.users ++ addrs.teams)
      // List owners (=receivers + sender)
      owners = if not(List.mem(key, receivers)) then [key|receivers] else receivers
      // Create status attribution.
      status =
        base = Message.Status.init(header, key) // Base status.
        base = {base with ~owners}
        senderbox = if (List.mem(key, addrs.users) || User.is_in_teams(key, addrs.teams)) then {inbox} else {sent}
        if (action == {draft}) then
          (owner -> { base with mbox={draft} labels=personal ~owner })
        else
          (owner ->
            if (owner == key) then
              { base with
                labels=personal opened=true mbox=senderbox
                moved={date=Date.now() from=senderbox}
                flags={read=true starred=false sent=true incopy=false} // Notice the 'sent' flag set to true.
                log="" }
            else
              { base with ~owner flags.incopy= List.mem(owner, incopy) })

      // Message is checked for user receivers only.
      match check_message(header, [key|addrs.users]) with
      | ~{failure} -> {failure=(failure, [])}
      | _ ->
        // Update internal user folder contents.
        do Search.finalize_index()

        do debug("Sending: {from} -> {to} + {cc} + {bcc}")
        do debug("Subject: {subject}")
        do debug("Security: {security}")
        do debug("Labels: {labels}")
        do debug("Content: {content}")
        do debug("Files: {files}")
        do debug("Status: {status}")
        do debug("External: {external}")

        message = ~{header status content owners}
        outcome = Message.add(some(key), message, [], true, action == {send}, encryption)
        match outcome with
        | {success=(mid, encrypted)} ->
          do Notification.Broadcast.received(mid, owners)
          // Add journal entries.
          _log =
            if action == {draft} then
              Journal.Message.log(key, mid, {draft= {new}}) |> ignore
            else
              _ = Journal.Main.log(
                message.header.creator,
                addrs.teams ++ addrs.users,
                { message= mid snippet=header.snippet
                  subject=header.subject from=from }
              )
              Journal.Message.log_send(message, is_reedit) |> ignore
          {success=(status(key), encrypted)}
        | {failure=e} ->
          {failure=(e, [])}
        end

  /**
   * Parse and validate message parameters, including:
   *   - security label
   *   - message to, cc, bcc
   * The result contains an indication as to whether the message should be encrypted or not.
   */
  @publish sendBefore(to, cc, bcc, security) =
    state = Login.get_state()
    if (not(Login.is_logged(state))) then
      {failure= (AppText.login_please(), [])}
    else
      match (Label.find(state.key, security, {class})) with
      | {some= security} ->
        encryption =
          match (security.category) with
          | {classified= ~{encrypt ...}} -> encrypt
          | _ -> false
          end
        security = security.id
        to = List.map(Message.Address.of_string, to)
        cc = List.map(Message.Address.of_string, cc)
        bcc = List.map(Message.Address.of_string, bcc)
        external =
          List.exists(Message.Address.is_external, to) ||
          List.exists(Message.Address.is_external, cc) ||
          List.exists(Message.Address.is_external, bcc)
        encryption = encryption && not(external)
        ~{encryption to cc bcc security key=state.key}
      | _ -> {failure= (@i18n("No security label defined"), [])}
      end

  /** Send a new mail (some parameters should have already been parsed by sendBefore). */
  @publish
  send(mid, thread, to, cc, bcc, subject, labels, security, content, files, mtype, is_reedit, encryption) =
    state = Login.get_state()
    key = state.key
    match User.get_email(key) with
    | {some= email} ->
      from = {internal= ~{key email team= false}}
      labels = List.filter_map(label ->
        Label.find(state.key, label, {shared}) |> Option.map(_.id, _)
        ,labels)
      // Send the mail.
      write(key, mid, thread, from, to, cc, bcc, subject, labels, security, content, files, mtype, is_reedit, encryption)
    | _ -> {failure= (AppText.user_not_found(), [])}
    end

  /**
   * Fetch reply parameters:
   *   - security label
   *   - message cc
   * The result contains the response's encryption.
   */
  @publish replyBefore(mid) =
    state = Login.get_state()
    if (not(Login.is_logged(state))) then
      {failure= (AppText.login_please(), [])}
    else
      match (Message.get(mid)) with
      | {some= message} ->
        from = Message.Address.name(message.from)
        thread = message.thread
        subject = message.subject
        subject =
          if String.has_prefix("Re:", subject) then subject
          else "Re: {subject}"
        date = Date.to_formatted_string(Date.generate_printer("%d.%m.%y %H:%M"), message.created)
        labels = List.filter(Label.check(_, Label.is_not_security), message.labels)
        encryption = message.encryption != {none}
        ~{encryption labels thread subject from date key=state.key cc=message.cc security=message.security}
      | _ -> {failure=(@i18n("Original message not found"), [])}
      end

  /**
   * Reply to a received mail.
   * The message parameters shoudl have been fetched through the method {replyBefore}.
   */
  @publish reply(mid, thread, to, cc, subject, content, labels, security, files, encryption) =
    state = Login.get_state()
    match User.get(state.key) with
    | {some= user} ->
      from = {internal= {key=state.key email=user.email team=false}}
      write(state.key, Message.genid(), some(thread), from, to, cc, [], subject, labels, security, content, files, {send}, false, encryption)
    | _ -> {failure= (AppText.user_not_found(), [])}
    end

  /** Send a draft.  Message encryption is disabled for now. */
  @server_private send_draft(state, mid: Message.id) =
    match (Message.get(mid)) with
    | {some= message} ->
        content = Message.get_content(message.id)
        write(
          state.key, mid, some(message.thread), message.from, message.to, message.cc, message.bcc,
          message.subject, message.labels, message.security, content, message.files, {send}, false, {none})
    | _ -> {failure= (AppText.Draft_not_found(), []) }
    end

  /** Send an internal mail. All recipients must be internal addresses. */
  @publish send_local_mail(to, subject, content, files) =
    state = Login.get_state()
    if (not(Login.is_logged(state))) then void
    else
      from = state.key
      id = Message.genid()
      header = ~{
        id ; parent= none; thread= id;
        creator= from; created= Date.now();
        from= User.get_address(from); to= [User.get_address(to)]; cc= []; bcc= [];
        subject; files; snippet= Utils.snippet(content, AppConfig.snippet_size)
        external= false; security= Label.notify.id; labels= [];
        encryption= {none}; headers= []; owners=[to]
      }
      status = Message.Status.init(header, _)
      Message.insert(~{header status owners=[to] content})

  /** {1} Construction and update of the badges. */

  /**
   * Fetch the message badges of the active user.
   * @param all if all is false, only the topbar badge will be returned.
   */
  @publish badges(all: bool) =
    state = Login.get_state()
    if Login.is_logged(state) then FolderController.badges(state.key, all)
    else Notification.nobadges

  /** {1} User actions **/

  /**
   * Switch the status of a message.
   * The caller should update the badges depending on the outcome.
   * @param force do not raise failure if status unchanged.
   * @return outcome with updated message if successful.
   */
  @private @server_private
  change_status(state, mid: Message.id, kind: Message.event, force: bool) =
    // Login check not needed.
    key = state.key
    match (Message.get_status(key, mid)) with
    | {none} ->
      do log("change_status: non existent or non accessible message")
      {failure= @i18n("non existent message")}
    | {some= status} ->
      // Update the user local information in the model.
      update(newstatus) =
        if (newstatus != status) then
          do debug("change_status: update: status updated for {mid},{key}")
          do Message.change_status(key, mid, newstatus)
          do FolderController.update_content(key, status, newstatus)
          do Notification.Broadcast.badges(state.key)
          {success= newstatus}
        else if (force) then
          {success= newstatus}
        else
          {failure= AppText.Failed()}

      match (kind) with
      // Mail deletion.
      | {delete= isdraft} ->
        // Delete mail file, and unindex the attachments.
        // do List.iter(hfid -> MailFile.detach(key, hfid, mid), message.files)
        log =
          if (isdraft) then Journal.Message.log(key, mid, {draft= {delete}})
          else              Journal.Message.log(key, mid, {mail= {delete}})
        newstatus = { status with ~log mbox={deleted=Date.now()} }
        update(newstatus)

      // Message box changes.
      | ~{from to} ->
        if (from == to) then update(status)
        else
          match (from, to) with

          // Untrash mail.
          | ({some= {trash}}, to) ->
            to = to ? status.moved.from
            src = Box.identifier({trash})
            dst = Box.identifier(to)
            log = Journal.Message.log(key, mid, {move= ~{src dst}})
            newstatus = { status with ~log mbox=to moved={date=Date.now() from={trash}} }
            update(newstatus)

          // Move mail.
          | (from, {some=to}) ->
            from = from ? status.mbox
            src = Box.identifier(from)
            dst = Box.identifier(to)
            do if (to == {trash} && status.flags.starred) then
              Journal.Message.log(key, mid, {star= false}) |> ignore
            do if (to == {trash} && status.flags.sent && status.mbox != {sent}) then
              Journal.Message.log(key, mid, {move= ~{src="SENT" dst="TRASH"}}) |> ignore
            log = Journal.Message.log(key, mid, {move= ~{src dst}})
            newstatus =
              if (to == {trash}) then
                { status with mbox=to moved={date=Date.now() ~from} flags.starred=false flags.sent=false ~log }
              else { status with mbox=to moved={date=Date.now() ~from} ~log }
            update(newstatus)

            // Other cases don't make sense.
            | _ -> update(status)
            end

          // Read / unread message.
          | ~{read} ->
            if (read == status.flags.read) then update(status)
            else
              log = Journal.Message.log(key, mid, ~{read})
              // If this is the first time the message has been opened by this user, update
              // the local information, and add a log entry.
              do if (read && not(status.opened)) then
                Journal.Message.log(key, mid, {opened=key}) |> ignore
              newstatus = { status with flags.read=read opened=true ~log }
              update(newstatus)

          // Flag / unflag message.
          | ~{star} ->
            if (star == status.flags.starred) then update(status)
            else
              log = Journal.Message.log(key, mid, ~{star})
              newstatus = { status with ~log flags.starred=star }
              update(newstatus)

          end

  /**
   * @param mbox an optional mail box. If a box is provided, check whether the mail [mid] is contained within,
   *   else just return the mail.
   * @param format format of the returned message. It can take the values
   *    - {full}: header + content + status
   *    - {header}: header + status
   *    - {content}: content
   *    - {minimal}: status
   * If the content is not loaded ({header} or {minimal} format), the message read status will not be updated.
   */
  @server_private open(state, mid: Message.id, mbox, format) =
    match Message.get_status(state.key, mid)
    | {none} -> {failure= AppText.Non_existent_message()}
    | {some=status} ->
      open_status(state, status, mbox, format)

  @server_private open_status(state, status, mbox, format) =
    isinbox =
      if mbox == some({starred}) then status.flags.starred
      else if mbox == some({sent}) then status.flags.sent || status.mbox == {sent}
      else mbox == none || mbox == some(status.mbox)
    isread = status.flags.read
    nocontent = format == {minimal} || format == {header}

    if not(isinbox) then
      {failure=AppText.Message_not_found()}
    else if not(user_can_read_message(state.key, status)) then
      {failure=AppText.not_allowed_message()}
    else if isread || nocontent then
      {success= Message.get_format(status, format)}
    else
      match (change_status(state, status.id, {read=true}, true)) with
      | ~{failure} -> ~{failure}
      | {success=status} -> {success= Message.get_format(status, format)}
      end

  /**
   * Fetch the message's status of the active user.
   * Triggers status changes as for message read.
   */
  @server_private get_status(state, mid: Message.id, format: Message.format) =
    key = state.key
    match Message.get_status(key, mid) with
    | {none} -> {failure= AppText.Non_existent_message()}
    | {some=status} ->

      if not(user_can_read_message(key, status)) then
        {failure=AppText.not_allowed_message()}
      else if status.flags.read then
        {success=status}
      else
        // If full mail recovery, update opened status.
        log =
          if (format != {minimal} && not(status.opened)) then
            Journal.Message.log(key, mid, {opened=key})
          else status.log
        newstatus = {status with opened=true ~log}
        do if (newstatus != status) then Message.change_status(key, mid, newstatus)
        {success=newstatus}

  /**
   * Update the labels attributed to a mail. Depending on the label:
   *   - if shared or security class, mail body is modified.
   *   - if local, only local state changed.
   */
  @publish
  update_labels(mid: Message.id, addLabels: list(Label.id), removeLabels: list(Label.id)) =
    state = Login.get_state()
    if (not(Login.is_logged(state))) then
      {failure= AppText.unauthorized()}
    else
      match (Message.get_status(state.key, mid), Message.get(mid), User.get(state.key)) with
      | ({none}, _, _)
      | (_, {none}, _) -> {failure= AppText.Non_existent_message()}
      | (_, _, {none}) -> {failure= AppText.Non_existent_user()}
      | ({some= status}, {some= header}, {some= user}) ->

        added = Label.categorize(Label.Sem.user_can_use_label(user, _), addLabels)
        removed = Label.categorize(Label.Sem.user_can_read_label(user, _), removeLabels)

        // do log("----- Input:")
        // do log("Add personal: {List.map(_.id, added.personal)}")
        // do log("Add shared: {List.map(_.id, added.shared)}")
        // do log("Add class: {List.map(_.id, added.class)}")
        // do log("Add error: {added.error}")
        // do log("Remove personal: {List.map(_.id, removed.personal)}")
        // do log("Remove shared: {List.map(_.id, removed.shared)}")
        // do log("Remove class: {List.map(_.id, removed.class)}")
        // do log("Remove error: {removed.error}")

        // Check nonexistent labels.
        if (added.error != [] || removed.error != []) then
          errlist = List.map(Label.sofid, added.error ++ removed.error) |> List.to_string_using("", "", ", ", _)
          {failure= @i18n("Undefined labels {errlist}")}
        else
          // do log("----- Previous state:")
          // do log("Shared labels: {message.labels}")
          // do log("Personal labels: {local.labels}")

          // Update shared labels.
          slabels =
            List.fold(lbl, acc -> List.remove(lbl.id, acc), removed.shared, header.labels) |>
            List.fold(lbl, acc -> if (not(List.mem(lbl.id, acc))) then [lbl.id|acc] else acc, added.shared, _)
          header = {header with labels=slabels}
          // Update personal labels.
          plabels =
            List.fold(lbl, acc -> List.remove(lbl.id, acc), removed.personal, status.labels) |>
            List.fold(lbl, acc -> if (not(List.mem(lbl.id, acc))) then [lbl.id|acc] else acc, added.personal, _)
          status = {status with labels=plabels}

          // do log("----- With updates:")
          // do log("Shared labels: {message.labels}")
          // do log("Personal labels: {plabels}")

          // Update security class.
          header =
            match (added.class, removed.class) with
            | ([], []) -> {success= header}
            | ([previous], [new]) ->
              // Update class.
              if (header.security == previous.id) then
                {success= {header with security=new.id}}
              else {failure= @i18n("Failed to update the security class of this message")}
            | _ -> {failure= @i18n("Failed to update the security class of this message")}
            end

          match (header) with
          | {success=header} ->
              // Add journal entries.
              entry = Journal.Message.log(state.key, mid, {label=
                { added= List.map(Label.sofid, addLabels);
                  removed= List.map(Label.sofid, removeLabels) }})
              status = {status with log= entry}
              // Make model changes.
              do Message.update(mid, header)
              do Message.change_status(state.key, mid, status)
              {success= (header, status)}
          | ~{failure} -> ~{failure}
          end
      end


  @publish empty_trash() =
    state = Login.get_state()
    if (Login.is_logged(state)) then
      trashed = Message.trashed(state.key)
      err = Iter.fold(mid, err ->
        match (delete(state, mid, false)) with
        | {success=_} -> err
        | {failure=_} -> [mid|err]
        end
      , trashed, [])
      if (err == []) then {success}
      else
        list = String.concat(",", err)
        {failure= @i18n("Failed to delete the following messages: {list}")}
    else
      {failure= AppText.login_please()}

  /** {1} Protected implementations. */

  @server_private delete(state, mid:Message.id, isdraft) = change_status(state, mid, {delete= isdraft}, false)
  @server_private star(state, mid:Message.id, star) = change_status(state, mid, ~{star}, false)
  @server_private read(state, mid:Message.id, read) = change_status(state, mid, ~{read}, false)
  @server_private trash(state, mid:Message.id) = change_status(state, mid, { from=none to={some={trash}} }, false)
  @server_private untrash(state, mid:Message.id) = change_status(state, mid, { from={some={trash}} to=none }, false)
  @server_private move(state, mid:Message.id, from:Mail.box, to:Mail.box) = change_status(state, mid, { from=some(from) to=some(to) }, false)

  /** {1} Published methods. */

  Exposed = {{
    @expand publish(method) =
    state = Login.get_state()
    if (not(Login.is_logged(state))) then {failure= AppText.login_please()}
    else method(state)

    @publish delete(mid: Message.id, isdraft) = MessageController.delete(_, mid, isdraft) |> publish
    @publish star(mid:Message.id, star) = MessageController.star(_, mid, star) |> publish
    @publish read(mid:Message.id, read) = MessageController.read(_, mid, read) |> publish
    @publish trash(mid:Message.id) = MessageController.trash(_, mid) |> publish
    @publish untrash(mid:Message.id) = MessageController.untrash(_, mid) |> publish
    @publish move(mid:Message.id, from, to) = MessageController.move(_, mid, from, to) |> publish
    @publish open(mid:Message.id, box, format) = MessageController.open(_, mid, box, format) |> publish
  }}

  /** {1} Asynchronized controller functions. */

  Async = {{

    @publish @async @expand send(mid, thread, to, cc, bcc, subject, labels, security, content, files, mtype, is_reedit, encryption, callback: ('a -> void)) =
      MessageController.send(mid, thread, to, cc, bcc, subject, labels, security, content, files, mtype, is_reedit, encryption) |> callback
    @publish @async @expand reply(mid, thread, to, cc, subject, content, labels, security, files, encryption, callback: ('a -> void)) =
      MessageController.reply(mid, thread, to, cc, subject, content, labels, security, files, encryption) |> callback

    @publish @async @expand move(mid, from, to, callback: ('a -> void)) = MessageController.Exposed.move(mid, from, to) |> callback
    @publish @async @expand delete(mid, isdraft, callback: ('a -> void)) = MessageController.Exposed.delete(mid, isdraft) |> callback
    @publish @async @expand star(mid, star, callback: ('a -> void)) = MessageController.Exposed.star(mid, star) |> callback
    @publish @async @expand read(mid, read, callback: ('a -> void)) = MessageController.Exposed.read(mid, read) |> callback
    @publish @async @expand open(mid, mbox, format, callback: ('a -> void)) = MessageController.Exposed.open(mid, mbox, format) |> callback

    @publish @async @expand update_labels(mid: Message.id, addLabels, removeLabels, callback: ('a -> void)) = MessageController.update_labels(mid, addLabels, removeLabels) |> callback
    @publish @async @expand empty_trash(callback: ('a -> void)) = MessageController.empty_trash() |> callback
  }}

}}
