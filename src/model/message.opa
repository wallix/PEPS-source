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


package com.mlstate.webmail.model
import stdlib.web.dns

/**
 * User mail addresses.
 * This type is used both internally and as client objects.
 */
type Mail.address =
  { Email.email external } or                                    // Strictly external users (typically addresses with distinct domains).
  { { User.key key, Email.email email, bool team } internal } or // Strictly internal users (with a key, and an address with the admin domain).
  { string unspecified }                                         // Undefined and partial addresses: for example addresses that can't be parsed.

/** Specifies the origin of a key. */
type Mail.Address.owner =
  {User.key user} or
  {Team.key team}

/**
 * User set flags.
 * More or less equivalent to IMAP flags.
 */
type Message.flags = {
  bool read,              // 'Local' read status.
  bool starred,
  bool sent,              // If actually sent by the user (not editable).
  bool incopy             // True iff the recipient was exclusively in cc / bcc.
}

/** Type of fetch requests. */
type Message.format =
  {full} or
  {minimal} or
  {raw}

/** Type of uploads. */
type Message.upload_type =
  {media} or
  {multipart} or
  {resumable}

/** Type of message related user actions. */
type Message.event =
   {option(Mail.box) from, option(Mail.box) to}  // Move a mail between folders.
or {bool read}                                   // Read / Unread a message.
or {bool star}                                   // Star / Unstar a message.
or {bool delete}                                 // Delete the mail (argument indicates whether the message is a draft).

type Message.id = DbUtils.oid
type Thread.id = DbUtils.oid

/**
 * Message encryption. If the encryption is not none,
 * the fields nonce and key will be set to the parameters
 * used for the encryption of the message. The key will be
 * either: the public key generated for the message
 * (in Message.header), or the encrypted secret key
 * (in Message.status).
 */
type Message.encryption =
  { string nonce,
    string key } or
  { none }

/**
 * Status attached to each internal owner of a message.
 * As of now, statuses are stored in a seperate map as of messages.
 */
type Message.status = {
  Message.id id,                                 // Id of the message.
  Thread.id thread,                              // Id of the thread.
  Date.date created,                             // Date of creation of the message (for query purposes).
  User.key creator,                              // Original owner of the message (for query purposes).
  Label.id security,                             // Security label of the message (for query purposes).
  User.key owner,                                // Owner of the message and of the status.
  list(User.key) owners,                         // List of the recipients of the original message (including the teams).
  bool lock,                                     // Prevent the status from being accessed.

  string subject,                                // Message subject.
  Mail.address from,                             // Message sender.
  string snippet,                                // Snippet of the message.
  list(File.id) files,                           // The file attachments.

  Mail.box mbox,
  {Date.date date, Mail.box from} moved,         // Date of the last movement.
  Message.flags flags,
  list(Label.id) labels,                         // List of PERSONAL labels only ; put SHARED labels in the field 'labels' of a message.
  bool opened,                                   // Set to true when message is first opened, never changed afterwards.
  Journal.id log,                                // Last journal entry referring to this message.
  /**
   * Secret key attributed to the message during its encryption.
   * This field is empty if no encryption was used, else is set
   * to an encrypted version of the secretKey, that can be read
   * only be the owner of this status.
   */
  Message.encryption encryption
}

/**
 * Type of messages as uploaded to and kept in the database.
 * Contains only those parts of the message as are common between each internal owner.
 */
type Message.header = {
  // Message metadata.
  Message.id id,
  User.key creator,
  Date.date created,
  // Standard mail information.
  Mail.address from,
  list(Mail.address) to,
  list(Mail.address) cc,
  list(Mail.address) bcc,
  string subject,
  // Snippet of the content.
  string snippet,
  // User specific information.
  // stringmap(Message.User.local) internal,
  // Set to true if at least one of the recipients is external.
  bool external,
  // List of internal owners (users and teams).
  list(User.key) owners,
  // Lock use for reedition purposes.
  // If lock is set, mail recipients cannot query the mail.
  // bool locked,
  Label.id security,
  // Labels contains only the shared labels, non security labels.
  Label.labels labels,
  // A file is used here since it gives us the possiblity
  // to easily update the attachment. The published version is the one used.
  list(File.id) files,
  // Thread id.
  Thread.id thread,
  // Parent message (in the same thread).
  option(Message.id) parent,
  // Parsed message headers; keep in webmail db for big data.
  Mime.headers headers,
  /**
   * Message encryption. See Message.encryption type
   * definition for more information.
   */
  Message.encryption encryption
}

/**
 * Contains the full mail information, and in particular all the
 * owners local information (mail boxes, flags).
 */
type Message.full = {
  Message.header header,            // Common parts.
  list(User.key) owners,            // List of internal owners (including teams).
  (User.key -> Message.status) status, // Determines the status of each internal owner.
  string content
}
type Message.local = {
  Message.header header,            // Common parts.
  Message.status status,            // Local parts.
  string content
}

/**
 * An even more lightweight message, which contains only the information needed to display
 * a message in the list.
 */
type Message.snippet = {
  Message.id id, Thread.id thread, Date.date created,
  Mail.address from, string subject,
  string snippet, list(File.id) files,
  Message.flags flags, Label.id security, // From the user status.
  // Highlightings.
  { option(string) subject,
    option(string) content,
    list(string) files } highlighted
}

/** A lightweight message used by the controller when not all the mail information is needed. */
type Message.partial = {
  Message.id id, Thread.id thread,
  string subject, User.key creator,
  bool external, Label.id security,
  Label.labels labels, list(File.id) files
}

type Message.Api.attachment = {
  // File attachments.
  string attachmentId,
  int size,
  string data
} or {
  // Mail body parts.
  int size,
  string data
}

type Message.Api.header = {string name, string value}
type Message.Api.headers = list(Message.Api.header)

type Message.Api.part = {
  string partId,
  string mimeType,
  string filename,
  Message.Api.headers headers,
  Message.Api.attachment body,
  Message.Api.parts parts
} or {
  string partId,
  string mimeType,
  Message.Api.headers headers,
  Message.Api.attachment body,
  Message.Api.parts parts
}

type Message.Api.parts = list(Message.Api.part)

type Message.Api.minimal = {
  string id,
  string threadId,
  list(string) labelIds,
  string snippet,
  string historyId,
  int sizeEstimate,
  string raw
}

type Message.Api.full = {
  string id,
  string threadId,
  list(string) labelIds,
  string snippet,
  string historyId,
  Message.Api.part payload,
  int sizeEstimate,
  string raw
}

type Message.Api.message = Message.Api.minimal or Message.Api.full

// Message header (common parts).
database Message.header /webmail/messages/header[{id}]
database /webmail/messages/header[_]/to full
database /webmail/messages/header[_]/cc full
database /webmail/messages/header[_]/bcc full
database /webmail/messages/header[_]/from full
database /webmail/messages/header[_]/external = false
database /webmail/messages/header[_]/encryption = {none}

// Message statuses (user specific metadata).
database Message.status /webmail/messages/status[{id, owner}]
database /webmail/messages/status[_]/opened = false
database /webmail/messages/status[_]/lock = false
database /webmail/messages/status[_]/flags full
database /webmail/messages/status[_]/from full
database /webmail/messages/status[_]/mbox full
database /webmail/messages/status[_]/moved full
database /webmail/messages/status[_]/encryption = {none}

// Message raw and content are stored in a separate path.
database stringmap(binary) /rawdata/messages/raw
database stringmap(string) /rawdata/messages/content

// TODO
database intset /webmail/threads

/**
 * Type of messages.
 * Messages are divided into three parts, placed in different mongo collections:
 *   - the message metadata, which includes sender, receivers, creation date and others, is common
 *     to all internal owners, and stored in the path /webmail/messages/header
 *   - the message status, which defines the mail box it is placed in, change log, flags and is
 *     specific to a single internal owner, is stored in /webmail/messages/status
 *   - the message content is stored separatly in /rawdata/message/content
 * For later referencing, the original rfc822 raw message is stored in /rawdata/messages/raw
 *
 * Messages are indexing in Solr so as to be searched by users.
 * Since we want to allow team users to search team messages as well as personal messages, without
 * the incurred cost of storing the list of team members in the message indexable, only the teams
 * are stored in the indexable, and users should search for team messages as well.
 * Consequently, all internal message owners must be stored in the indexable, and not only the searchable
 * ones (for whom the message is stored in a searchable mail box). This means the search results must be filtered
 * according to the mail box.
 */

module Message {

  /** {1} Utils */

  log = Log.notice("[Message]", _)
  debug = Log.debug("[Message]", _)
  warning = Log.warning("[Message]", _)
  error = Log.error("[Message]", _)

  exposed function genid() { DbUtils.OID.genuid() }
  @stringifier(Message.id) function string sofmid(Message.id id) { DbUtils.OID.sofid(id) }
  @expand function Message.id midofs(string s) { DbUtils.OID.idofs(s) }

  Message.id dummy = ""

  /** Create a page from a list of client messages. */
  make_page = function {
    case []: {elts: [], first: Date.now(), last: Date.now(), more: false, size: 0}
    case messages:
      first = List.head(messages).created
      last = Utils.last(messages).created
      ~{elts: messages, first, last, more: false, size: List.length(messages)}
  }

  /** {1} Address conversions. */

  module Address {

    /** Identify a given local identifier. */
    function identify(string local) {
      match (DbUtils.option(/webmail/users[email.address.local == local]/key)) {
        case {some: user}: some(~{user})
        default:
          match (DbUtils.option(/webmail/teams[email.address.local == local]/key)) {
            case {some: team}: some(~{team})
            default: none
          }
      }
    }

    /** Sort a list of addresses by kind. */
    function categorize(list(Mail.address) addrs) {
      init = {unspecified: [], users: [], teams: [], external: []}
      cat = List.fold(function (addr, acc) {
        match (addr) {
          case {external: email}: {acc with external: [email|acc.external]}
          case {internal: ~{key, email, team: {false}}}: {acc with users: [key|acc.users]}
          case {internal: ~{key, email, team: {true}}}: {acc with teams: [key|acc.teams]}
          case {unspecified: s}: {acc with unspecified: [s|acc.unspecified]}
        }
      }, addrs, init)
      { external: List.unique_list_of(cat.external),
        users: List.unique_list_of(cat.users),
        teams: List.unique_list_of(cat.teams),
        unspecified: cat.unspecified }
    }

    /**
     * Build a reply list. The reply list contains the provided addresses, filtered to remove all
     * unspecified recipients. User recipients already represented by one of the team recipients
     * are equally removed.
     */
    function replyto(list(Mail.address) addrs) {
      init = {users: [], teams: [], external: []}
      cat = List.fold(function (addr, acc) {
        match (addr) {
          case {external: email}: {acc with external: [addr|acc.external]}
          case {internal: ~{key, email, team: {false}}}: {acc with users: [addr|acc.users]}
          case {internal: ~{key, email, team: {true}}}: {acc with teams: [addr|acc.teams]}
          case {unspecified: s}: acc
        }
      }, addrs, init)
      addrs = {
        external: List.unique_list_of(cat.external),
        users: List.unique_list_of(cat.users),
        teams: List.unique_list_of(cat.teams)
      }

      if (addrs.teams == [] || addrs.users == [])
        addrs.teams ++ addrs.users ++ addrs.external
      else {
        teams = List.filter_map(key, addrs.teams)
        users = List.filter_map(function (addr) {
          match (addr) {
            case {internal: ~{key ...}}:
              if (User.is_in_teams(key, teams)) none
              else some(addr)
            default: some(addr)
          }
        }, addrs.users)
        addrs.teams ++ users ++ addrs.external
      }
    }

    /**
     * Given a mail address, return
     *  - an external address if the domain is different
     *  - an internal address if the domain is the admin domain, and if
     *     the address is attributed to an internal user.
     *  - unspecified if no user owns this address.
     */
    function Mail.address of_email(Email.email email) {
      if (email.address.domain == Admin.get_domain())
        match (identify(email.address.local)) {
          case {some: ~{user}}: User.get_address(user)
          case {some: ~{team}}: Team.get_address(team)
          default: {unspecified: Email.to_string(email)}
        }
      else {external: email}
    }

    /** Email parsing. */
    function Mail.address of_string(string s) {
      match (Email.of_string_opt(s)) {
        case {some: email}: of_email(email)
        default:
          // s is assumed to be the local part of a mail address.
          match (identify(s)) {
            case {some: ~{user}}: User.get_address(user)
            case {some: ~{team}}: Team.get_address(team)
            default: {unspecified: s}
          }
      }
    }

    /** Return, if defined, the email identified by the given address. */
    function email(Mail.address addr) {
      match (addr) {
        case {internal: ~{email ...}}
        case {external: email}: some(email)
        default: none
      }
    }

    /** Return the name of the email's user. */
    function string name(Mail.address addr) {
      match (addr) {
        case {internal: ~{email ...}}
        case {external: email}: Email.to_name(email)
        default: ""
      }
    }

    /** Return the key if the user is internal. */
    function key(Mail.address addr) {
      match (addr) {
        case {internal: ~{key ...}}: some(key)
        default: none
      }
    }
    function keys(list(Mail.address) addrs) { List.filter_map(key, addrs) }

    /** Return true iff the address is the internal recipient with given key. */
    function haskey(Mail.address addr, User.key user) {
      match (addr) {
        case {internal: ~{key ...}}: key == user
        default: false
      }
    }

    /** Print the email identified by the address. */
    function to_string(Mail.address addr) {
      match (addr) {
        case {internal: ~{email ...}}
        case {external: email}: Email.to_string(email)
        default: ""
      }
    }

    /**
     * Convert the address to an html span element.
     * @param nameonly indicates whether to display the address or the name.
     */
    both function to_html(addr, option(int) limit, bool nameonly) {
      if (nameonly)
        match (addr) {
          case {unspecified: s}: <span class="ext_mail">{s}</span>
          case {external: email}:
            address = Email.to_string_only_address(email)
            label = Email.to_name(email) |> Utils.string_limit_opt(limit, _)
            <span class="ext_mail" title={address} data-placement="bottom" rel="tooltip">{label}</span>
          case {internal: ~{email ...}}:
            address = Email.to_string_only_address(email)
            name = Email.to_name(email) |> Utils.string_limit_opt(limit, _)
            <span class="int_mail" title={address} data-placement="bottom" rel="tooltip">{name}</span>
        }
      else
        match (addr) {
          case {unspecified: addr}: <>{addr}</>
          case {external: email}: <span class="ext_mail">{Email.to_string(email)}</span>
          case {internal: ~{email ...}}: <span class="int_mail">{Email.to_string(email)}</span>
        }
    }

    /** Comma separated list of emails. */
    function list_to_string(list(Mail.address) addrs) {
      List.map(to_string, addrs) |> List.to_string_using("", "", ",", _)
    }

    /** Properties. */

    is_internal = function {
      case {internal: _}: true
      default: false
    }
    is_external = function {
      case {external: _}: true
      default: false
    }
    is_specified = function {
      case {unspecified: _}: false
      default: true
    }
    function has_key(Mail.address addr, User.key user) {
      match (addr) {
        case {internal: ~{key ...}}: user == key
        default: false
      }
    }

  } // END ADDRESS


  /** {1} Message statuses. */

  module Status {

    /** Initial information of any user. */
    function Message.status init(Message.header message, User.key owner) { ~{
      owner, id: message.id, thread: message.thread, creator: message.creator,
      security: message.security, created: message.created,

      subject: message.subject, from: message.from,
      snippet: message.snippet, files: message.files,

      opened: false, lock: false, owners: message.owners,
      moved: {date: Date.now(), from: {inbox}},
      mbox: {inbox}, labels: [], log: "",
      flags: {read: false, starred: false, sent: false, incopy: false},
      encryption: {none}
    } }

  } // END STATUS


  /** {1} Mail creation. */

  function Message.header make(creator, id, from, to, cc, bcc, subject, date, content) { ~{
    id, thread: id, parent: none, from, to, cc, bcc,
    subject, creator, created: date ? Date.now(),
    external: false, owners: [], security: Label.open.id,
    labels: [], files: [], headers : [],
    snippet : Utils.snippet(content, AppConfig.snippet_size),
    encryption: {none}
  } }

  /** Extract the fields needed for the message list display. */
  function snippet(status) { {
    snippet: status.snippet, created: status.created,
    files: status.files, id: status.id, thread: status.thread,
    from: status.from, subject: status.subject,
    flags: status.flags, security: status.security,
    highlighted: {subject: none, content: none, files: []}
  } }

  /** Add empty highlightings to a message snippet. */
  function highlight(status, subject, content, files) { {
    id: status.id, from: status.from, flags: status.flags,
    subject: status.subject, created: status.created, thread: status.thread,
    snippet: status.snippet, files: status.files, security: status.security,
    highlighted: ~{subject, content, files}
  } }

  /**
   * Encrypt a single message. This method inputs a full message with
   * header, status and content, and returns a modified message with:
   *
   *  - header with updated field {encryption}
   *  - updated user statuses
   *
   * The content is encrypted client side.
   *
   * @param encryption is none if the message is not encrypted, and contains
   *  the message key pair plus the nonce used in the content encryption else.
   */
  function encrypt(Message.full message, encryption) {
    match (encryption) {
      case ~{publicKey, secretKey, nonce}:
        // Message encryption.
        encryption = ~{key: publicKey, nonce}
        messageSecretKey = Uint8Array.decodeBase64(secretKey)
        // Encrypt the secret key for each receiver.
        status = function (owner) {
          if (owner == User.dummy) message.status(owner)
          else {
            log("encrypt: generating key for user {owner}")
            // Disambiguation between user and team publicKeys is performed
            // by the function User.publicKey.
            publicKey = Uint8Array.decodeBase64(User.publicKey(owner))
            nonce = TweetNacl.randomBytes(TweetNacl.Box.nonceLength)
            log("encrypt: userPublicKey={Uint8Array.encodeBase64(publicKey)}")
            secretKey = TweetNacl.Box.box(messageSecretKey, nonce, publicKey, messageSecretKey)
            log("encrypt: encryptedSecretKey={Uint8Array.encodeBase64(secretKey)}")
            encryption = {
              key: Uint8Array.encodeBase64(secretKey),
              nonce: Uint8Array.encodeBase64(nonce)
            }
            {message.status(owner) with ~encryption}
          }
        }
        // Return the updated message.
        { header: {message.header with ~encryption}, ~status,
          owners: message.owners, content: message.content }
      default: message
    }
  }

  /**
   * Message decryption is performed client side.
   * Check function MessageView.decrypt for more information.
   */

  /**
   * Extract the list of recipients of a message reply.
   * Recipients are sorted by category (team or user), and only user recipients
   * not already present in the teams are added to the reply list.
   */
  function make_reply_list(key, mbox, message) {
    mfrom = message.from
    mto = message.to
    l = Address.replyto(
      if (mbox == {sent} || Address.has_key(mfrom, key)) mto
      else [mfrom|mto]
    )
    if (l == []) [mfrom] else l
  }

  /**
   * Insert a message in the database.
   * TODO: add status for team members, pass statuses as argument.
   */
  function insert(Message.full message) {
    log("insert: MID={message.header.id} owners={String.concat(",",message.owners)}")
    mid = message.header.id
    /webmail/messages/header[id == mid] <- {message.header with owners: message.owners}
    /rawdata/messages/content[mid] <- message.content
    List.iter(function (owner) {
      // Team statuses should only be inserted if the message is encrypted.
      // if (not(Team.key_exists(owner) && message.header.encryption == {none}))
      /webmail/messages/status[~{owner, id: mid}] <- message.status(owner)
    }, message.owners)
    // Reference status.
    /webmail/messages/status[{owner: User.dummy, id: mid}] <- message.status(User.dummy)
    get_partial_cached.invalidate(mid)
    get_cached.invalidate(mid)
  }

  /**
   * Create acceess tokens of the attachments for each of the internal recipients.
   * For team recipients, the files are shared with the team, and placed in the team folder.
   *
   * @param inline a list of inlined files, which will appear as hidden to mail recipients.
   */
  function share_attachments(Message.full message, list(File.id) inline) {
    mid = message.header.id
    // Extract file metadata, fetch tokens of encrypted files.
    // If the file raw or the encryption parameters are missing,
    // the attachemnt is dropped.
    files =
      if (message.owners != [])
        List.filter_map(function (fid) {
          match (File.get_raw_metadata(fid)) {
            case {some: ~{
              id, name, size, mimetype, created, thumbnail,
              encryption: {key: filePublicKey, nonce: fileNonce}
            }}:
              // Fetch corresponding token.
              match (FileToken.findEncryption(id, message.header.creator)) {
                case {key: fileSecretKey, ~nonce}:
                  some((fid, ~{
                    id, name, size, mimetype, created, thumbnail,
                    encryption: ~{filePublicKey, fileSecretKey, fileNonce, nonce}
                  }))
                default: none // File won't be readable anyway.
              }
            case {some: ~{id, name, size, mimetype, created, thumbnail, encryption: {none}}}:
              some((fid, ~{id, name, size, mimetype, created, thumbnail, encryption: {none}}))
            default: none // File is missing.
          }
        }, message.header.files)
      else []

    List.fold(function (key, encrypted) {
      // For team recipients, create a file attachment in the team directory.
      // Other recipients receive the file in the Attached folder.
      dir =
        if (Team.key_exists(key)) Team.get_directory(key)
        else Directory.create_from_path(key, ["Attached"])
      addr = User.get_address(key)
      // Message sender already has one copy of the file.
      if (addr != message.header.from)
        match (dir) {
          case {some: dir}:
            List.fold(function((fid, meta), encrypted) {
              hidden = List.mem(fid, inline)
              MailFile.attach(key, fid, mid)
              token = FileToken.create(key, {email: mid}, fid, meta, {read}, {some: dir}, hidden, {none}, true)
              match (meta.encryption) {
                case ~{filePublicKey, fileSecretKey, fileNonce, nonce}:
                  log("share_attachments: encrypted file {fid}")
                  userPublicKey = User.publicKey(key)
                  [~{file: token.id, filePublicKey, fileSecretKey, fileNonce, nonce, user: key, userPublicKey} | encrypted]
                case {none}: encrypted
              }
            }, files, encrypted)
          default: encrypted
        }
      else encrypted
    }, message.owners, [])
  }

  /**
   * Add the recipients of a mail to the contact list.
   * It also increments the use count if the contact already exists.
   */
  private function mark_contacts(User.key key, Message.full message) {
    header = message.header
    from = Message.Address.email(header.from)

    function mark(mails) {
      List.iter(function {
        case { external : email }:
          if (not(Contact.mark(key, email.address, 10))) Contact.new(key, email.name, email.address, {secret})
        case { internal : ~{key: dkey, email, team: false} }:
          if (key != dkey) {
            if (not(Contact.mark(key, email.address, 10))) Contact.new(key, email.name, email.address, {secret})
            Option.iter(function (email) {
              if (not(Contact.mark(dkey, email.address, 1))) Contact.new(dkey, email.name, email.address, {secret})
            }, from)
          }
        default: void
      }, mails)
    }
    mark(header.to)
    mark(header.cc)
    mark(header.bcc)
  }

  /**
   * Add a new message to the database.
   * Caution: the message id should be defined beforehand.
   * @param key optional mail sender.
   *    E.g. messages received through SMTP should leave this field undefined.
   *    Other options ([send_external], [update_contact]) can only be executed if a user is specified.
   * @param encryption activate message encryption.
   */
  function add(option(User.key) key, Message.full message, list(File.id) inline, bool update_contact, bool external, encryption) {
    oldstatus = Option.bind(Message.get_status(_, message.header.id), key)
    isdraft = Option.map(_.mbox, oldstatus) == some({draft})
    mid = message.header.id
    // Erase previous statuses (message reedition).
    // NB: team messages cannot be reedited, so we don't have the hassle
    // of doing that for all team members.
    DbSet.iterator(/webmail/messages/status[id == mid and lock == true]) |>
    Iter.iter(function (status) { Db.remove(@/webmail/messages/status[{id: mid, owner: status.owner}]) }, _)
    // Share attachments.
    encrypted = share_attachments(message, inline)
    // Update folder contents.
    if (isdraft) Option.iter(Folder.delete_message(key ? "", _), oldstatus) // Remove from drafts.
    Folder.insert_messages(message.owners, message.status)
    // Encrypt the message if required.
    message = encrypt(message, encryption)
    // Insert message.
    insert(message)
    // Index message in solr.
    Search.Message.Async.index(key ? "", message, ignore)

    match (Option.bind(User.get, key)) {
      case {none}: void
        // No log added for external actions. (like SMTP incoming messages).
        // WebmailLogger.webmail(user, message, "add")
      case {some: user}:
        from =
          match (message.header.from) {
            case { external: email }
            case { internal: ~{email ...} }: email
            default: user.email
          }
        // Send to external recipients.
        if (external) Message.send(user.key, from, message)
        if (update_contact) mark_contacts(user.key, message)
    }

    {success : (message.header.id, encrypted)}
  }

  /** {1} Setters. */

  /**
   * Replace the lock flag previously used.
   * Attempts to lock the message:
   *  - if the message has external recipients, it cannot be reedited.
   *  - check if the message has been opened by anyone but the message sender.
   *  - if not, remove the statuses of each internal owner.
   */
  function bool lock(Message.id mid, User.key sender) {
    external = ?/webmail/messages/header[id == mid]/external ? true
    opened = DbUtils.option(/webmail/messages/status[id == mid and owner != sender and opened == true; limit 1])
    if (not(external) && opened == none) {
      // Update folder counts.
      DbSet.iterator(/webmail/messages/status[id == mid and owner != sender]) |>
      Iter.iter(function (status) { Folder.delete_message(status.owner, status) }, _)
      // Dismiss dashboard notification.
      Journal.Main.unlog(sender, mid)
      // Lock statuses.
      /webmail/messages/status[id == mid and owner != sender] <- {lock: true}
      true
    } else false
  }

  /**
   * Unlock a message previously locked by the {Message.lock}.
   * @param owner user trying to unlock the message. This user must have unlocked access to the message.
   * @return true iff the lock was successfully removed.
   */
  function unlock(User.key owner, Message.id mid) {
    if (not(?/webmail/messages/status[~{id: mid, owner}]/lock ? true)) {
      // Retrieve status information enough to remake the journal log.
      info = {
        date: Date.now(),
        event: {
          message: mid, snippet: "",
          subject: "", from: {unspecified: ""}
        },
        owners: []
      }
      info =
        DbSet.iterator(/webmail/messages/status[id == mid and lock == true]) |>
        Iter.fold(function (status, info) {
          if (status.owner != "") {
            // Restore folder counts.
            Folder.insert_message(status.owner, status)
            { date: status.created,
              owners: [status.owner|info.owners],
              event: {
                message: mid, snippet: status.snippet,
                subject: status.subject, from: status.from
              } }
          } else info
        }, _, info)
      // Restore dashboard notification.
      Journal.Main.logDated(owner, info.owners, info.event, info.date) |> ignore
      // Unlock statuses.
      /webmail/messages/status[id == mid] <- {lock: false}
    }
  }

  /** {1} Getters. */

  private function priv_get(Message.id mid) { ?/webmail/messages/header[id == mid] }
  private function priv_get_partial(Message.id mid) {
    ?/webmail/messages/header[id == mid].{id, thread, subject, creator, security, labels, external, files }
  }

  private get_cached = AppCache.sized_cache(100, priv_get)
  private get_partial_cached = AppCache.sized_cache(100, priv_get_partial)

  @expand function get(Message.id mid) { get_cached.get(mid) }
  @expand function get_partial(Message.id mid) { get_partial_cached.get(mid) }

  function has_external_owners(Message.id mid) { ?/webmail/messages/header[id == mid]/external ? true }
  function get_files(Message.id mid)   { ?/webmail/messages/header[id == mid].{files} }
  function get_content(Message.id mid) { /rawdata/messages/content[mid] }

  /** Return the publicKey associated with a message (or an empty uint8array). */
  function publicKey(Message.id mid) {
    match (?/webmail/messages/header[id == mid]/encryption) {
      case {some: ~{key ...}}: Uint8Array.decodeBase64(key)
      default: Uint8Array.decodeBase64("")
    }
  }

  /** Return true iff the message is encrypted. */
  function encryption(Message.id mid) {
    match (?/webmail/messages/header[id == mid]/encryption) {
      case {some: ~{key, nonce}}: true
      default: false
    }
  }

  /**
   * Fetch the message status of the given user.
   * If the user does not have a status yet, but can still access the message through one of his teams,
   * a new status is generated matching that team status (in which case the secret is recomputed to match
   * the user's keyPair).
   */
  function get_status(User.key key, Message.id mid) {
    status = DbUtils.option(/webmail/messages/status[owner == key and id == mid and lock == false])
    match (status) {
      case ~{some}: ~{some}
      default:
        teams = User.get_teams(key)
        // Fetch one team status.
        status = DbUtils.option(/webmail/messages/status[owner in teams and id == mid and lock == false; limit 1])
        match (status) {
          case {some: status}:
            // If the message is encrypted, we must re-encrypt the message secret key for
            // the new user. The secret key is obtained from the team status, and reencoded
            // for the user.
            status = match(status.encryption) {
              case ~{nonce, key: messageSecretKey}:
                log("get_status: MID={mid}: extending permission of team {status.owner} for user {key}")
                // Decrypt the secret key owned by the team.
                messagePublicKey = publicKey(mid)
                messageSecretKey = Team.decrypt(status.owner, messageSecretKey, nonce, messagePublicKey)
                match (messageSecretKey) {
                  case {some: messageSecretKey}:
                    // Reencrypt the secret key for the user.
                    publicKey = User.publicKey(key) |> Uint8Array.decodeBase64
                    nonce = TweetNacl.randomBytes(TweetNacl.Box.nonceLength)
                    secretKey = TweetNacl.Box.box(messageSecretKey, nonce, publicKey, messageSecretKey)
                    encryption = {
                      key: Uint8Array.encodeBase64(secretKey),
                      nonce: Uint8Array.encodeBase64(nonce)
                    }
                    ~{status with owner: key, ~encryption}
                  default: status
                }
              // Message is not crypted.
              default: {status with owner: key}
            }
            // Insert the user status.
            change_status(key, mid, status)
            some({status with owner: key})
          default: none
        }
    }
  }

  /**
   * Return a partial message, as indicated by the provided format.
   * The format can be:
   *  - {full}: content + header + status. if the header cannot be recovered, the result will
   *    be the same as with minimal format.
   *  - {minimal}: status
   *  - {content}: content
   */
  function get_format(Message.status status, format) {
    match (format) {
      case {minimal}: ~{status}
      case {content}:
        content = get_content(status.id)
        ~{content}
      case {header}:
        match (get(status.id)) {
          case {some: header}: ~{header, status}
          default: ~{status}
        }
      case {full}:
        match (get(status.id)) {
          case {some: header}:
            content = get_content(status.id)
            ~{status, header, content}
          default: ~{status}
        }
    }
  }

  /** Return the full message, complete with content. */
  // function get_full(Message.status status) {
  //   content = get_content(status.id)
  //   header = get(status.id)
  //   match (header) {
  //     case {some: header}: some(~{header, status, content})
  //     default: none
  //   }
  // }

  /** {1} Queries. */

  /** Return the total number of messages stored in the database. */
  function count() { DbSet.iterator(/webmail/messages/header.{}) |> Iter.count }
  /** Return all the messages. Access to this function should be restricted. */
  function all() { DbSet.iterator(/webmail/messages/header) }
  /** Test the emptiness of a given user's mail box. */
  function is_empty(User.key key) { DbUtils.option(/webmail/messages/status[owner == key; limit 1].{}) |> Option.is_none }

  /**
   * Return the list of internal message owners (statuses).
   * NB: team owners are not included in the result of the query.
   */
  function get_owners(Message.id mid)   { ?/webmail/messages/header[id == mid]/owners ? [] }
  function get_statuses(Message.id mid, list(User.key) owners) {
    if (owners == []) DbSet.iterator(/webmail/messages/status[id == mid]) |> Iter.to_list
    else DbSet.iterator(/webmail/messages/status[id == mid and (owner in owners)]) |> Iter.to_list
  }

  /* Mails that can be read by a user are those:
   *   - which have the user as owner
   *   - whose security label can be read by the user
   * All user readable security labels are passed to the query, to be able to check in mogo
   * which messages are effectively readable.
   */

  /**
   * Identify messages bearing a particular label.
   * @return the unordered list of readable messages with the provided label.
   */
  function all_with_label(User.key key, Label.id lbl) {
    readable = Label.Sem.readable_labels(key)
    DbSet.iterator(/webmail/messages/status[owner == key and labels[_] == lbl and (creator == key or (security in readable))])
  }

  /**
   * List messages from the provided mail box.
   * @return the unordered list of readable messages of the provided mail box.
   */
  function all_in_mbox(User.key key, Mail.box box) {
    readable = Label.Sem.readable_labels(key)
    match (box) {
      case {starred}: DbSet.iterator(/webmail/messages/status[owner == key and flags.starred == true and (creator == key or (security in readable))])
      case {sent}:    DbSet.iterator(/webmail/messages/status[owner == key and (flags.sent == true or mbox == {sent}) and (creator == key or (security in readable))])
      default:        DbSet.iterator(/webmail/messages/status[owner == key and mbox == box and (creator == key or (security in readable))])
    }
  }

  /** List messages from a given thread. */
  function all_in_thread(User.key key, Thread.id id) {
    readable = Label.Sem.readable_labels(key)
    teams = User.get_teams(key)
    // Fetch statuses.
    statuses = DbSet.iterator(/webmail/messages/status[
      thread == id and (owner == key or (owner == User.dummy and owners[_] in teams)) and
      lock == false and (creator == key or (security in readable)) and not(mbox.deleted exists); order +created
    ]) |> compress(key, _) |> Iter.to_list
    // Fetch associated headers.
    mids = List.map(_.id, statuses)
    headers = DbSet.iterator(/webmail/messages/header[
      id in mids; order +created
    ]) |> Iter.to_list
    // Join results.
    List.map2(function (status, header) { ~{status, header} }, statuses, headers)
  }

  /**
   * Filter search results. The queries are similar to the ones sent by {ranged_in_mbox}, but filter
   * message ids and attachments as well.
   *
   * @return snippets of the search results.
   */
  function search(list(Message.id) mids, list(FileToken.id) fids, User.key key, Mail.box box) {
    readable = Label.Sem.readable_labels(key)
    match (box) {
      case {starred}:
        DbSet.iterator(/webmail/messages/status[
          owner == key and flags.starred == true and lock == false  and
          (creator == key or (security in readable)) and (id in mids or files[_] in fids); order -created
        ])
      case {sent}:
        DbSet.iterator(/webmail/messages/status[
          owner == key and (flags.sent == true or mbox == {sent}) and lock == false and
          (creator == key or (security in readable)) and (id in mids or files[_] in fids); order -created
        ])
      case {inbox}:
        teams = User.get_teams(key)
        DbSet.iterator(/webmail/messages/status[
          ((owner == key and mbox == box) or (owner == User.dummy and owners[_] in teams)) and lock == false and
          (creator == key or (security in readable)) and (id in mids or files[_] in fids); order -created
        ]) |> compress(key, _)
      default:
        DbSet.iterator(/webmail/messages/status[
          owner == key and mbox == box and lock == false  and (creator == key or (security in readable)) and
          (id in mids or files[_] in fids); order -created
        ])
    }
  }

  /**
   * Main query function: fetches messages from a mail box, to be displayed to the active user.
   * If the box is the inbox, statuses from the user teams are checked as well, to check for new team messages.
   *
   * If the input box is the {inbox}, two queries are sent for: one to determine which messages the user already has access
   * to, and the second to fetch team messages that haven't been read by the user.
   *
   * @param box the source mail box.
   * @param range the maximum number of returned results
   * @param before limit the search to the messages received after {before}
   *
   * @return the list of such messages.
   */
  function ranged_in_mbox(User.key key, Mail.box box, Date.date before, int range) {
    readable = Label.Sem.readable_labels(key)
    match (box) {
      case {starred}:
        DbSet.iterator(/webmail/messages/status[
          owner == key and flags.starred == true and created < before and lock == false  and
          (creator == key or (security in readable)); limit range; order -created
        ])
      case {sent}:
        DbSet.iterator(/webmail/messages/status[
          owner == key and (flags.sent == true or mbox == {sent}) and created < before and
          lock == false  and (creator == key or (security in readable)); limit range; order -created
        ])
      case {inbox}:
        teams = User.get_teams(key)
        DbSet.iterator(/webmail/messages/status[
          ((owner == key and mbox == box) or (owner == User.dummy and owners[_] in teams)) and created < before and
          lock == false and (creator == key or (security in readable)); limit range; order -created
        ]) |> compress(key, _)
      default:
        DbSet.iterator(/webmail/messages/status[
          owner == key and mbox == box and created < before and lock == false  and
          (creator == key or (security in readable)); limit range; order -created
        ])
    }
  }

  /**
   * Remove duplicates from the list of message status.
   * @param key owner which identifies privileged statuses.
   */
  private function compress(User.key key, iter) {
    recursive function option((Message.status, iter(Message.status))) next(iter(Message.status) iter, mid, mstatus) {
      match (iter.next()) {
        case {some: (status, iter)}:
          if (status.id == mid && status.owner == key)  next(iter, mid, status)
          else if (status.id == mid)                    next(iter, mid, mstatus)
          else                                          some((mstatus, {next: function () { next(iter, status.id, status) }}))
        default:                                        some((mstatus, Iter.empty))
      }
    }
    // Init the compression.
    match (iter.next()) {
      case {some: (status, iter)}: {next: function () { next(iter, status.id, status) }}
      default: Iter.empty
    }
  }

  /** Return the full list of trashed messages (no security check). */
  function trashed(User.key key) {
    DbSet.iterator(/webmail/messages/status[owner == key and mbox == {trash}]/id)
  }

  /**
   * Return the full list of readable user messages (only the status part).
   * This function has an application in folder reindexing.
   */
  function list(User.key key) {
    readable = Label.Sem.readable_labels(key)
    DbSet.iterator(/webmail/messages/status[owner == key and (creator == key or (security in readable))])
  }

  /** Check if message is starred by the given user (defaults to false if non-existent message). */
  function is_starred(User.key owner, Message.id id) {
    match (?/webmail/messages/status[~{owner, id}]/flags) {
      case {some: flags}: flags.starred
      default: false
    }
  }

  /** {1} Modifiers. */

  /** Update the status of a single message owner. */
  function change_status(User.key owner, Message.id id, Message.status status) {
    /webmail/messages/status[~{owner, id}] <- status
  }

  /** Remove the status attached to a message owner. */
  function remove(User.key owner, Message.id id) {
    Db.remove(@/webmail/messages/status[~{owner, id}])
    Search.Message.unindex(sofmid(id), owner) |> ignore
  }

  /**
   * Swap the lock of user messages accessible through some teams.
   * @param lock if true, messages are locked, else restored.
   * @param diff the varying teams.
   * @param teams either the new or old set of teams, depending on the lock condition.
   */
  function swap(User.key owner, mbox, diff, teams, bool lock) {
    // (un)lock messages accessible only trough {diff}.
    (mids, contents) =
      DbSet.iterator(/webmail/messages/status[
        owner == owner and mbox == mbox and
        not(owners[_] == owner) and not(owners[_] in teams) and
        owners[_] in diff and lock == not(lock)
      ]) |>
      Iter.fold(function (status, (mids, contents)) {
        ( [ status.id|mids ],
          { count: contents.count+1,
            starred: contents.starred+(if (status.flags.starred) 1 else 0),
            unread: contents.unread+(if (status.flags.read) 0 else 1),
            new: 0 } )
      }, _, ([], {count: 0, starred: 0, unread: 0, new: 0}))
    // Effectively (un)lock the messages.
    if (mids != [])
      /webmail/messages/status[owner == owner and id in mids] <- ~{lock}
    // Add messages with no instanciated status to the contents, and return the results.
    if (mbox == {inbox}) {
      mdiff = DbSet.iterator(/webmail/messages/status[
        owner == User.dummy and not(owners[_] == owner) and not(owners[_] in teams) and owners[_] in diff
      ].{}) |> Iter.count

      { new: mdiff-contents.count, count: mdiff,
        unread: contents.unread+mdiff-contents.count, starred: contents.starred }
    } else contents
  }

  /**
   * Update the fields contained in the partial message. Fields that are mutable: security, external, labels.
   * Changes of the security label are propagated to the different owner statuses.
   */
  function update(Message.id id, header) {
    oldsecurity = ?/webmail/messages/header[id == id]/security
    // Propagate security changes.
    if (oldsecurity != some(header.security))
      /webmail/messages/status[id == id] <- {security: header.security}
    // Update the common parts of the message.
    /webmail/messages/header[id == id] <- {external: header.external, security: header.security, labels: header.labels}
    get_cached.invalidate(id)
    get_partial_cached.invalidate(id)
  }

  /** {1} Mail sending. */

  private function filter_external(emails) {
    List.filter_map(
      function {
        case { external : email }: some(email)
        default: none
      }, emails)
  }

  function allow_internet(message) {
    security = Option.map(_.category, Label.get(message.security))
    match (security) {
      case {some: {unprotected: internet}}: internet
      default: false
    }
  }

  /**
   * Send a message to external recipients.
   * @return void
   */
  @async
  function send(User.key key, Email.email from, Message.full message) {
    header = message.header
    if (not(header.external) || not(allow_internet(header))) void
    else {
      smtp_options = {
        SmtpClient.default_options with
        host: AppParameters.parameters.smtp_out_host,
        port: AppParameters.parameters.smtp_out_port
      }
      version = Label.XIMF.version
      name = Label.XIMF.name
      security = Label.XIMF.make_security_label(header)
      files = List.filter_map(File.getResource, header.files)
      mail_options =
       ~{ from,
          to: filter_external(header.to),
          cc: filter_external(header.cc),
          bcc: filter_external(header.bcc),
          subject: header.subject,
          custom_headers:
            if (not(AppConfig.has_security_labels)) []
            else [version, name] ++ security,
          files: files }

      /** Wait for the mail send status, and call the callback function
       * with the adequate value. */
      function void send_callback(Email.send_status status) {
        log("send: success")
        Journal.Message.log(key, header.id, {send: status}) |> ignore
      }
      // Send the mail. nodemailer does all the job.
      log("send: try send message")
      log("send: with options {smtp_options}")
      log("send: with headers {mail_options}")
      SmtpClient.try_send_async(mail_options, {text: message.content}, smtp_options, send_callback)
    }
  }

  /** Asynchronous equivalent functions. */
  module Async {
    @async function add(key, message, inline, update_contact, send_external, encryption, ('a -> void) callback) {
      Message.add(key, message, inline, update_contact, send_external, encryption) |> callback
    }
  } // END ASYNC

  /** {1} API accessors. */

  module Api {

    /**
     * Return the status encoded by a list of labels.
     * If mutiple mailboxes are present, only the first one is kept.
     * By default, the mail is placed in the {inbox}.
     */
    function local_of_labels(User.key key, list(string) labels) {
      (unread, labels) =
        if (List.mem("UNREAD", labels)) (true, List.remove("UNREAD", labels)) else (false, labels)
      (starred, labels) =
        if (List.mem("STARRED", labels)) (true, List.remove("STARRED", labels)) else (false, labels)
      mbox = match (labels) {
        case [lbl | _]: Box.iparse(lbl)
        default: {inbox}
      }
     ~{ opened: not(unread),
        moved: {from: mbox, date: Date.now()},
        mbox,
        flags: ~{read: not(unread), starred}
      }
    }

    /** Compute the size estimate of a mail body part. */
    function header_size(Message.Api.header header)         { 4*(String.length(header.name) + String.length(header.value)) }
    function headers_size(list(Message.Api.header) headers) { List.fold(function (header, acc) { acc + header_size(header) }, headers, 0) }
    function part_size(Message.Api.part part) {
      match (part) {
        case ~{partId, mimeType, headers, body: ~{size ...}, parts, filename ...}
        case ~{partId, mimeType, headers, body: ~{size ...} , parts ...}:
          tmp = 4*(String.length(partId) + String.length(mimeType)) + headers_size(headers) + size
          List.fold(function (part, acc) { acc + part_size(part) }, parts, tmp)
      }
    }

    /**
     * For the purpose of the rest api. The message is converted to a json value, with the same
     * format used by Gmail for its api. The main difference is the addition of a security field.
     * @param format one of {full}, {minimal} or {raw}
     */
    function ({Message.Api.full full} or {Message.Api.minimal minimal} or {string failure}) message_to_resource(User.key key, Message.status status, format) {
      // Construction of the mail.
      match (get(status.id)) {
        case {some: message}:
          log("Message.Api.get: status={status}")
          content = Message.get_content(message.id)
          labels =
            (if (not(status.flags.read)) ["UNREAD"] else []) ++
            (if (status.flags.starred) ["STARRED"] else []) ++
            [Box.identifier(status.mbox) | List.map(Label.sofid, status.labels ++ message.labels)]
          snippet = message.snippet
          lastchange =
            Journal.Message.last_modification(key, message.id) |>
            Option.map(function (last) { Journal.sofid(last.id) }, _)

          // Payload construction.
          body = {
            partId: "0.0",
            mimeType: "text/plain",
            headers: [],
            body: {size: 4*String.length(content), data: content},
            parts: []
          }
          files = List.fold(function (file, (i, acc)) {
            match (File.getPayload(file, "0.{i}")) {
              case {some: part}: (i+1, [part|acc])
              default: (i, acc)
            }
          }, message.files, (1, [])).f2 |> List.rev

          ximf =
            [Label.XIMF.version, Label.XIMF.name] ++ Label.XIMF.make_security_label(message) |>
            List.map(function ((name, value)) { ~{name, value} }, _)
          Message.Api.part payload = {
            partId: "0", // Not used.
            mimeType: "multipart/mixed",
            headers: [
              {name: "From", value: Address.to_string(message.from)},
              {name: "To", value: Address.list_to_string(message.to)},
              {name: "Cc", value: Address.list_to_string(message.cc)},
              {name: "Bcc", value: Address.list_to_string(message.bcc)},
              {name: "Subject", value: message.subject},
              {name: "Date", value: "{message.created}"}
            ] ++ ximf,
            body: {size: 0, data: ""},
            parts: (Message.Api.parts [body|files])
          }
          // Common parts.
          estimate = part_size(payload)
          resource = {
            id: "{message.id}",
            threadId: "{message.thread}",
            labelIds: labels,
            ~snippet,
            historyId: status.log,
            sizeEstimate: estimate,
            raw: ""
          }
          match (format) {
            case {minimal}:
              {minimal: resource}
            case {full}:
              {full: Message.Api.full {resource extend ~payload}}
            case {raw}:
              {failure: @i18n("Not implemented: raw format")}
          }
        default:
          {failure: @i18n("Cannot access message")}
      }
    }

  } // END API

}
