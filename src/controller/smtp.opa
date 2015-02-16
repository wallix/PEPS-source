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

module SmtpController {

  private function log(msg) { Log.notice("SMTP: ", msg) }
  private function warning(msg) { Log.warning("SMTP :", msg) }
  private function debug(msg) { Log.debug("SMTP :", msg) }

  /** Convert the given data, with the given charset, to utf-8 format. */
  function string_to_utf8(charset, string data) {
    bdata = Binary.of_binary(data)
    match (Iconv.convert_to_utf8(charset, bdata)) {
      case {none}: data
      case {some: res}: res
    }
  }
  function binary_to_utf8(charset, binary data) {
    match (Iconv.convert_to_utf8(charset, data)) {
      case {none}: Binary.to_binary(data)
      case {some: res}: res
    }
  }

  /** Parse the mime headers. */
  module Header {

    function decode_name(e) {
      match (e.name) {
        case {some: n}:
          name = Mime.Header.decode_value(n, string_to_utf8)
          { e with name: some(name) }
        default: e
      }
    }

    function extract_from(Mime.headers headers) {
      match (Mime.Header.find("From", headers)) {
        case {some: from}:
          match (Email.of_string_opt(from)) {
            case {some: f}:
              f = decode_name(f)
              Message.Address.of_email(f)
            default: {unspecified: from}
          }
        default: {unspecified: ""}
      }
    }

    function extract_mail_list(name, headers) {
      match (Mime.Header.find(name, headers)) {
        case {some: addrs}:
          addrs = String.explode(",", addrs)
          List.fold(function (addr, acc) {
            match (Email.of_string_opt(String.trim(addr))) {
              case {some: t}:
                t = decode_name(t)
                [Message.Address.of_email(t) | acc]
              default: acc
            }
          }, addrs, [])
        default: []
      }
    }

    function extract_string(name, headers) { Mime.Header.find(name, headers) ? "" }

  } // END HEADER

  /**
   * Extract the attachment parts of the MIME. Though this function has already been implemented in the
   * standard library, it does not return the content disposition associated with such parts.
   */
  // private function get_attachments_aux(Mime.entity entity, decoder, acc) {
  //   match (entity.body) {
  //     case {plain: _}
  //     case {html: _}: acc
  //     case ~{attachment}:
  //       disposition = Mime.Header.find("Content-Disposition", entity.headers) ? "inline"
  //       attachment = ({attachment with filename: Mime.Header.decode_value(attachment.filename, decoder)}, disposition)
  //       [attachment|acc]
  //     case {multipart: parts}:
  //       List.fold(get_attachments_aux(_, decoder, _), parts, acc)
  //   }
  // }

  // function get_attachments(Mime.entity entity, decoder) { get_attachments_aux(entity, decoder, []) }

  /**
   * Date parsing.
   * Some messages were found to have a different date format than that specified by RFC 2822,
   * so instead of using just one parser, a list is defined and each is tested in turn.
   */

  date_trimmer = { parser { s = (!" (" .)* (" (" (!")" .)* ")")? : Text.to_string(Text.ltconcat(s)) } }
  /** Several date scanners, by order of preference. */
  date_scanners = [
    Date.generate_scanner("%a, %d %b %Y %T %z"),
    Date.generate_scanner("%d %b %Y %T %z"),
    Date.generate_scanner("%d %b %y %T %Z")
  ]

  function parse_date(string date) {
    if (date == "") none
    else
      match (Parser.try_parse(date_trimmer, date)) {
        case {none}: none
        case {some: date}:
          List.fold(function (scanner, parsed) {
            match (parsed) {
              case {none}: Date.of_formatted_string(scanner, date) // GMT.
                //   case {some: gmt_date}:
                //     offset = Duration.between(Date.now(), Date.now())
                //     {some: Date.advance(gmt_date, offset)}
                //   default: none
                // }
              case {some: date}: {some: date}
            }
          }, date_scanners, none)
      }
  }

  /**
   * Build a message from parsed MIME data.
   * The message is not added to the database, but returned instead.
   * @param user user performing the operation.
   * @param recipients list of local addresses that were listed as recipients of the SMTP message.
   * @param flags additional information: read, starred, mailbox.
   */
  function message_of_mime(User.key user, mime, recipients, flags) {
    headers = mime.content.headers
    body = mime.content.body

    from = Header.extract_from(headers)
    to = Header.extract_mail_list("To", headers)
    cc = Header.extract_mail_list("Cc", headers)
    bcc = Header.extract_mail_list("Bcc", headers)
    date = Header.extract_string("Date", headers)
    mime_id = Header.extract_string("Message-ID", headers)
    content = Mime.get_text(mime, binary_to_utf8)

    debug("From: {Message.Address.email(from)}")
    debug("To: {List.map(Message.Address.email, to) |> List.to_string}")
    debug("Cc: {List.map(Message.Address.email, cc) |> List.to_string}")
    debug("Bcc: {List.map(Message.Address.email, bcc) |> List.to_string}")
    debug("Date: {date}")
    debug("Message-ID: {mime_id}")

    subject = Header.extract_string("Subject", headers)
    debug("Subject: {subject}")
    subject = Mime.Header.decode_value(subject, string_to_utf8)
    debug("Decoded Subject: {subject}")

    recipients = List.filter_map(function (addr) {
      match (Email.of_string_opt(String.trim(addr))) {
        case {some: t}:
          t = Header.decode_name(t)
          {some: Message.Address.of_email(t)}
        default: none
      }
    }, recipients)

    // Build the message header.
    date = parse_date(date)
    header = Message.make(user, Message.genid(), from, to, cc, bcc, subject, date, content)
    sender = Message.Address.key(from)
    // List of mail receivers.
    incopy = cc ++ bcc
    receivers =
      List.filter_map(Message.Address.key, recipients ++ to ++ incopy) |>
      List.unique_list_of |>
      MessageController.remove_blocking(Message.Address.email(from), _)
    incopy = Message.Address.keys(incopy)
    // Status attribution.
    senderreceiver = Option.map(List.mem(_, receivers), sender) ? false
    userreceiver = List.mem(user, receivers)
    // List owners.
    owners = if (senderreceiver) receivers else match (sender) { case {some: sender}: [sender | receivers] ; default: receivers }
    owners = if (userreceiver || some(user) == sender) owners else [user | owners]
    // Status generator.
    status =
      base = {
        Message.Status.init(header, user) with
        opened: flags.seen, flags: {read: flags.seen, starred: flags.flagged, sent: false, incopy: false}
      }
      base = {base with ~owners}
      senderbox = if (senderreceiver) {{inbox}} else {{sent}}
      function (owner) {
        if (sender == some(owner))
          { base with
            ~owner, opened: true, mbox: senderbox,
            moved: {date: Date.now(), from: senderbox},
            flags: {read: true, starred: false, sent: true, incopy: false} } // Notice the 'sent' flag set to true.
        else if (owner == user && not(userreceiver))
          { base with flags.read: true, opened: true }
        else
          { base with ~owner, flags.incopy: List.mem(owner, incopy) }
      }

    // [hidden] is the list of attachements corresponding to icons in the message html, and which
    // should be hidden in the directory view.
    attachments = Mime.get_attachments(mime, string_to_utf8)
    (files, hidden) =
      List.fold(function (attachment, (files, hidden)) {
        content = attachment.data
        id = File.create(user, attachment.filename, attachment.mimetype, content, Label.attached.id).file.id
        hide =
          String.has_prefix("image0", attachment.filename) ||
          "invite.ics" == attachment.filename
        if (hide) ([id|files], [id|hidden])
        else ([id|files], hidden)
      }, attachments, ([], []))

    (~{header: ~{header with files, security: Label.open.id}, status, content, owners}, hidden)
  }

  private function get(field, r, def) { StringMap.get(field, r) ? def }
  private function getopt(field, r) { StringMap.get(field, r) }
  private function getmap(field, r, f) { StringMap.get(field, r) |> Option.bind(f, _) }

  /** Parse a message of mimetype application/json. */
  function metadata_of_json(Mime.headers headers, string charset, binary data) {

    json = Json.of_string(binary_to_utf8(charset, data))
    match (json) {
      case {some: json}:
        record = match (json) {
          case {Record: r}: StringMap.From.assoc_list(r)
          default: StringMap.empty
        }
        raw = get("raw", record, {String: ""})
        sizeEstimate = getmap("sizeEstimate", record, JsonOpa.to_int)
        snippet = get("snippet", record, {String: ""})
        id = get("id", record, {String: ""})
        threadId = get("threadId", record, {String: ""})
        labelIds = getmap("labelIds", record, JsonOpa.to_list)
        historyId = get("historyId", record, {String: ""})
        payload = getmap("payload", record, JsonOpa.to_list)
        void

      default: void
    }
  }

  /**
   * Parse attachments.
   * The JSON value represent a (potentially incomplete) mail part. Only when the part
   * contains an attachment is the value returned.
   */
  function option(Message.Api.attachment) attachment_of_json(RPC.Json.json json) {
    OpaSerialize.Json.unserialize_unsorted(json)
  }

  /**
   * Parse an incoming mail, with the MIME format (rfc822).
   * @param user override the mail receiver / sender as the one performing the action.
   * @param recipients list of SMTP recipients.
   * @param user user performing the action.
   */
  function parse(option(User.key) user, string raw, list(string) recipients) {
    function to_address(MailParser.address email) {
      match (Email.address_of_string_opt(email.address)) {
        case {some: address}:
          Message.Address.of_email(~{address, name: email.name})
        default: {unspecified: email.address}
      }
    }

    mail = @catch(function (err) {
      warning("MailParser returned a parsing error: {err}")
      none
    }, MailParser.parsesync(raw))

    match (mail) {
      case {some: mail}:
        from =
          match (mail.from) {
            case [email|_]: to_address(email)
            default: {unspecified: ""}
          }
        to = List.map(to_address, mail.to)
        cc = List.map(to_address, mail.cc)
        bcc = List.map(to_address, mail.bcc)
        incopy = cc ++ bcc
        sender = Message.Address.key(from)
        creator = user ? sender ? ""

        // Keep the text content, if any, or convert the html content, if necessary.
        content =
          if (mail.text == "")
            HtmlToText.convert(mail.html, {wordwrap: 130, tables: {all}})
          else mail.text

        date =
          match (MailParser.get_header(mail, "Date")) {
            case {some: header}: parse_date(List.head(header.value))
            default: none
          }

        header = Message.make(creator, Message.genid(), from, to, cc, bcc, mail.subject, date, content)

        recipients = List.rev_map(function (addr) {
          match (Email.of_string_opt(String.trim(addr))) {
            case {some: t}: Header.decode_name(t) |> Message.Address.of_email
            default: {unspecified: addr}
          }
        }, recipients)

        // Compute the list of internal receivers.
        receivers =
          List.filter_map(Message.Address.key, to ++ incopy ++ recipients) |>
          List.unique_list_of |>
          MessageController.remove_blocking(Message.Address.email(from), _)
        incopy = Message.Address.keys(incopy)
        // Status attribution.
        senderreceiver = Option.map(List.mem(_, receivers), sender) ? false
        userreceiver = Option.map(List.mem(_, receivers), user) ? false
        // List owners.
        owners = if (senderreceiver) receivers else match (sender) { case {some: sender}: [sender | receivers] ; default: receivers }
        owners = if (userreceiver || user == sender) owners else match (user) { case {some: user}: [user | owners] ; default: owners }
        // Status generator.
        status =
          base = Message.Status.init(header, creator)
          base = {base with ~owners}
          senderbox = if (senderreceiver) {{inbox}} else {{sent}}
          function (owner) {
            if (sender == some(owner))
              { base with
                ~owner, opened: true, mbox: senderbox,
                moved: {date: Date.now(), from: senderbox},
                flags: {read: true, starred: false, sent: true, incopy: false} } // Notice the 'sent' flag set to true.
            else if (user == some(owner) && not(userreceiver))
              { base with ~owner, flags.read: true, opened: true }
            else
              { base with ~owner, flags.incopy: List.mem(owner, incopy) }
          }

        // [hidden] is the list of attachements corresponding to icons in the message html, and which
        // should be hidden in the directory view.
        (files, hidden) =
          List.fold(function (attachment, (files, hidden)) {
            id = File.create(creator, attachment.fileName, attachment.contentType, attachment.content, Label.attached.id).file.id
            hide =
              String.has_prefix("image0", attachment.fileName) ||
              "invite.ics" == attachment.fileName
            if (hide) ([id|files], [id|hidden])
            else ([id|files], hidden)
          }, mail.attachments, ([], []))

        some((~{ header: ~{header with files, security: Label.open.id}, content, status, owners}, hidden))
      default: none
    }
  }

  /** Parse and insert an incoming message. */
  function receive() {
    // Extract the request body.
    url = HttpRequest.get_url()
    headers = HttpRequest.get_headers()
    content_type = Option.bind(_.header_get("Content-Type"), headers)
    content_transfer_encoding = Option.bind(_.header_get("Content-Transfer-Encoding"), headers) ? ""
    body =
      if (String.lowercase(content_transfer_encoding) == "base64")
        HttpRequest.get_body() |> Option.map(Binary.of_base64, _) |> Option.map(Binary.to_string, _)
      else HttpRequest.get_body()
    t0 = Date.now()
    // Parse the multipart message/
    match (Option.bind(parse(none, _, []), body)) {
      case {some: (message, inline)}:
        t1 = Date.now()
        blength = String.byte_length(message.content)
        if (blength < AppConfig.message_max_size) {
          Message.Async.add(none, message, inline, false, false, {none}, function {
            case {success: (mid, _encrypted)}:
              Notification.Broadcast.received(mid, message.owners)
              // Add journal entries.
              Journal.Main.log(
                message.header.creator, message.owners,
                { message: mid, snippet: message.header.snippet,
                  subject: message.header.subject, from: message.header.from }) |> ignore
              Journal.Message.log_send(message, false) |> ignore
            default: void
          })


          Resource.raw_response("\{\}", "application/json", {success})
        } else {
          warning("receive: Oversized message body: {blength} > authorized {AppConfig.message_max_size}")
          Resource.raw_response("\{\}", "application/json", {bad_request})
        }
      default:
        warning("receive: Corrupt mime content")
        Resource.raw_response("\{\}", "application/json", {bad_request})
    }
  }

}
