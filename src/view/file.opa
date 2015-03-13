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

module FileView {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[FileView]", msg) }
  private function debug(msg) { Log.debug("[FileView]", msg) }
  private function warning(msg) { Log.warning("[FileView]", msg) }
  private function error(msg) { Log.error("[FileView]", msg) }

  both function mimetype_to_icon(string mimetype) {
    Parser.parse(parser {
      case "application/pdf" : "fa-file-o"
      case "application/doc" : "fa-file-o"
      case "application/xls" : "fa-file-o"
      case "text/" .* : "fa-file-o"
      case .* : "fa-file-o"
    }, mimetype)
  }

  both private function mimetype_to_doctype(string mimetype) {
    Parser.parse(parser {
      case "image/" .* : {img}
      case "text/html" : {html}
      case "text/plain" : {txt}
      case "application/pdf" : {pdf}
      case .* : {verbatim}
    }, mimetype)
  }

  /** Create a div containing a thumbnail that will load after the page is ready. */
  protected function thumbnail(token) {
    match (token.thumbnail) {
      case {some: thumbnail}: <div class="file-thumbnail"><img src="/thumbnail/{token.active}"/></div>
      default: <div class="file-thumbnail"><i class="fa fa-file-o"/></div>
    }
  }

  /** {1} File line rendering. */

  module Line {

    /**
     * Build the requested column element.
     * @param raw must provide the minimal handset of fields contained in {RawFile.metadata}
     */
    function render_column(Login.state state, FileToken.t token, Path.t path, option(Share.t) share, Table.column column) {
      match (column) {
        case {name: {inert}}:
          {xhtml:
            <div id="file-{token.id}" class="file-block pull-left o-selectable context"
                data-toggle="context" data-target="#context_menu_content">
              <span class="fa fa-lg {FileView.mimetype_to_icon(token.mimetype)}"></span>
              <a id="{token.id}-name" class="file o-selectable" title="{token.name.fullname}">{token.name.fullname}</a>
            </div>}
        case {name: {immediate: onclick}}:
          name = token.name.fullname
          fullname = Path.fullname(path, name) // FIXME: If search only.
          attachment = {file: ~{id: token.file, name, size: token.size, mimetype: token.mimetype}}
          cbid = Random.string(10)
          {xhtml:
            <div id="file-{token.id}" class="file-block pull-left o-selectable context"
                onclick={onclick(cbid, attachment, _)}
                data-toggle="context" data-target="#context_menu_content">
              <a id="{token.id}-name" class="file o-selectable" title="{fullname}" target="_blank">{fullname}</a>
            </div>}
        case {name: ~{link}}:
          name = token.name.fullname
          sanname = Uri.encode_string(name)
          url =
            match (link) {
              case {shared}:
                base = Directory.urn(path, share) |> URN.print
                "{base}/{sanname}"
              case {team}
              case {personal}:
                sanid = Uri.encode_string(RawFile.sofid(token.active))
                "/raw/{sanid}/{sanname}"
            }
          {xhtml:
            <div id="file-{token.id}" class="file-block pull-left o-selectable context"
                data-toggle="context" data-target="#context_menu_content">
              {thumbnail(token)}
              <a id="{token.id}-name" class="file o-selectable" href="{url}" target="_blank" title="{name}">{name}</a>
            </div>}
        case {created}:
          {xhtml:
            <span id="file-{token.id}-created" class="file_uploaded o-selectable"
                onready={Misc.insert_timer("file-{token.id}-created", token.created)}></span>}
        case {edited}:
          {xhtml:
              <span id="file-{token.id}-edited" class="file_uploaded o-selectable"
                onready={Misc.insert_timer("file-{token.id}-edited", token.edited)}></span>}
        case {owner: {team}}: {xhtml: <>{Team.get_name(token.owner) ? token.owner}</>}
        case {owner: {user}}: {xhtml: <>{User.get_username(token.owner) ? token.owner}</>}
        case {origin}:
          match (token.origin) {
            case {shared: by}: {xhtml: <>{User.get_username(by) ? by}</>}
            case {upload}: {xhtml: <>{"me"}</>}
            case {email: _}: {xhtml: <>{"attachment"}</>}
            default: {xhtml: <>{"not shared"}</>}
          }
        case {size}:
          { xhtml: <span class="file_size o-selectable">{Utils.print_size(token.size)}</span>,
            decorator: Xhtml.add_attribute_unsafe("data-size", "{token.size}", _) }
        case {mimetype}: {xhtml: <span class="file_kind o-selectable">{Utils.string_limit(35, token.mimetype)}</span>}
        case {class}:
          security =
            match (File.get_security(token.file)) {
              case {some: id}: Label.to_client(id) |> LabelView.make_label(_, none)
              default: <></>
            }
          {xhtml: <span class="file_labels o-selectable">{security}</span>}
        case {link}: {xhtml: ShareView.make_link(token, share)}
        case {checkbox: onclick}:
          cbid = Random.string(10)
          attachment = {file: ~{id: token.file, name: token.name.fullname, size: token.size, mimetype: token.mimetype}}
          {xhtml: <span><input type="checkbox" id="fccb_{cbid}" onclick={onclick(cbid, attachment,_)}></input></span>}
      }
    }

    function WBootstrap.Table.line render(FileToken.t token, Path.t path, option(Share.t) share, handles, Table.line line) {
      state = Login.get_state()
      Table.render(
        render_column(state, token, path, share, _),
        handles(token.id, token.name.fullname, token.access, token.security, token.dir, [], token.file), // FIXME
        line
      )
    }
  } // END FILE


  /** {1} Callbacks. */

  /**
   * Most operations are shared between files and directories.
   * This module gathers such operations.
   */
  module Common {

    /** Rename a token or directory. */
    client function rename(src) {
      id = Share.id(src)
      isdir = Share.isdir(src)
      name = Dom.get_text(#{"{id}-name"})
      match (Client.prompt(@i18n("Rename {name} into ?"), name)) {
        case {some: ""}: void
        case {some: newname}:
          Dom.set_text(#{"{id}-name"}, newname)
          FSController.Async.rename(src, newname, function {
            // Client side.
            case {success: setname}:
              if (setname != newname) Dom.set_text(#{"{id}-name"}, setname)  // In case a version was added.
              Dom.set_attribute_unsafe(#{"{id}-name"}, "title", setname)     // Update the title.
            case ~{failure}:
              title = if (isdir) AppText.Folder() else AppText.File()
              Dom.set_text(#{"{id}-name"}, name)
              Notifications.error(@i18n("{title} renaming failure"), <>{failure.message}</>)
          })
        default: void
      }
    }

    /** Delete a token or directory. */
    client function delete(src) {
      id = Share.id(src)
      name = Dom.get_text(#{"{id}-name"})
      if (Client.confirm(@i18n("Are you sure you want to delete '{name}'?"))) {
        isdir = Share.isdir(src)
        FSController.Async.delete(src, function {
          // Client side.
          case {success: parent}: load_directory(parent)
          case ~{failure}:
            title = if (isdir) AppText.Folder() else AppText.File()
            Notifications.error(@i18n("{title} deletion failure"), <>{failure.message}</>)
        })
      }
    }

    /** {2} Moves. */

    /**
     * Move a resource to the selected destination.
     * In general, the resource can be moved to all directories, albeit with some restrictions
     * inherent to shared folders. That is not true however for team resources that can only be moved
     * to team folders (to keep a separate structure).
     */
    client function moveTo(src, name, dst) {
      dst = if (dst == Directory.rootid) none else some(dst)
      isdir = Share.isdir(src)
      FSController.Async.move(src, dst, function {
        // Client side.
        case {success: (state, parent, parameters)}:
          load_directory(parent)           // Refresh view.
          reencrypt(state.key, parameters) // Validate encryption of shared copies.
        case ~{failure}:
          title = if (isdir) AppText.Directory() else AppText.File()
          Notifications.error(@i18n("{title} move failure"), <>{failure.message}</>)
      })
    }
    /** Select a move destination. */
    exposed function move(src, name, previous)(_evt) {
      owner = Share.switch(src, FileToken.get_owner, Directory.get_owner)
      DirChooser.create(~{
        title: @i18n("Move file {name} to directory..."),
        action: moveTo(src, name, _), user: owner,
        excluded: match (previous) { case {some: d}: [Directory.sofid(d)]; default: [] }
      })
    }

    /**
     * {2} Sharing.
     *
     * TODO: add link to files in the notification mail.
     * TODO: selection of user access rights. (default is {admin} for now).
     */

    /**
     * Callback of the sharing function.
     * Re-encrypt the shared encrypted files, so that sharees may access their copy.
     * Encryption parameters, returned by the sharing function, are decoded using the suer secretKey,
     * and returned to the server to be uploaded to the database.
     */
    client function reencrypt(User.key sharer, parameters) {
      // No encrypted files -> do nothing.
      if (parameters == []) void
      else
        UserView.SecretKey.prompt(sharer, @i18n("Please enter your password to complete sharing."), function {
          case {some: secretKey}:
            // Compute the new encryption parameters.
            parameters = List.filter_map(function (encryption) {
              log("reencrypt: reencrypting file {encryption.file} for user {encryption.user}")
              // Some decoding.
              nonce = Uint8Array.decodeBase64(encryption.nonce)
              filePublicKey = Uint8Array.decodeBase64(encryption.filePublicKey)
              fileSecretKey = Uint8Array.decodeBase64(encryption.fileSecretKey)
              userPublicKey = Uint8Array.decodeBase64(encryption.userPublicKey)
              // Unbox the file secret key.
              match (TweetNacl.Box.open(fileSecretKey, nonce, filePublicKey, secretKey)) {
                // Decryption successfull.
                case {some: fileSecretKey}:
                  // Re-encrypt the secret key for the new owner.
                  nonce = TweetNacl.randomBytes(TweetNacl.Box.nonceLength)
                  fileSecretKey = TweetNacl.Box.box(fileSecretKey, nonce, userPublicKey, fileSecretKey)
                  newencryption = {
                    nonce: Uint8Array.encodeBase64(nonce),
                    key: Uint8Array.encodeBase64(fileSecretKey)
                  }
                  some({
                    file: encryption.file,
                    encryption: newencryption
                  })
                // Decryption failed.
                default:
                  none
              }
            }, parameters)
            // Push the new encryption parameters to the server.
            if (parameters != [])
              FileTokenController.Async.reencrypt(parameters, function {
                case {success}: Notifications.success(@i18n("Sharing completed"), <>{@i18n("The sharing has been successfully completed.")}</>)
                case {failure: msg}: Notifications.error(@i18n("Sharing failure"), <>{msg}</>)
              })
          // Sharing cancelled.
          // TODO: destroy copies of the encrypted files.
          default: void
        })
    }

    /**
     * Share a FS resource with a list of users. Depending on the encryption of the shared files,
     * a second step may be needed to re-rencrypt the files for each user ({reencrypt} method).
     */
    client function shareWith(Share.source src, string name, Label.id security, access)(_evt) {
      function action(User.key user, list(User.key) sharees) {
        FSController.Async.shareWith(src, sharees, access, function {
          case {success: parameters}: reencrypt(user, parameters)
          case {failure: msg}: Notifications.error(@i18n("Sharing failure"), <>{msg}</>)
        })
      }
      UserChooser.create({
        title: @i18n("Share file {name} with"),
        immediate: false,
        callback: ~{ action, text: "Share" },
        custom: security,
        exclude: []
      })
    }

    /** Link creation. */
    client function share(Share.source src)(_evt) {
      id = Share.id(src)
      FSController.Async.share(src, function {
        // Client side.
        case {success: (parent, link)}:
          Client.winopen("/share/{link}", {_blank}, [], true) |> ignore
          load_directory(parent) // Add link to view ?
        case ~{failure}: Notifications.error(@i18n("Sharing failure"), <>{failure.message}</>)
      })
    }

    /** Link deletion. */
    client function unshare(string link)(_evt) {
      FSController.Async.unshare(link, function {
        // Client side.
        case {success}:
          urn = URN.get()
          match (urn.mode) {
            case {files: "links"}: Content.refresh()
            default: Content.update({mode: {files: "links"}, path: urn.path}, true)
          }
        case ~{failure}: Notifications.error(@i18n("Unsharing failure"), <>{failure.message}</>)
      })
    }

  } // END COMMON

  /** {1} File specific operations. */

  /**
   * Upload a file to the active directory.
   * Read the files upload via UploadView.modal.
   */
  client function upload(where, _evt) {
    Button.loading(#upload_button)
    files = AttachedRef.list("upload")
    if (files == []) {
      Notifications.error(@i18n("Upload failure"), <>{AppText.no_files_provided()}</>)
      Button.reset(#upload_button)
    } else {
      security = Dom.get_attribute_unsafe(#file_class, "title")
      FSController.upload(files, where, security, function {
        // Client side.
        case {success: (parent, files)}:
          UploadView.clear("upload")
          Modal.hide(#modal_upload)
          load_directory(parent)
        case ~{failure}:
          Notifications.error(@i18n("Upload failure"), <>{failure.message}</>)
          Button.reset(#upload_button)
      })
    }
  }

  /**
   * {2 Publication and update.}
   *
   * Updates change the active version, but the local modifications themselves are not discarded.
   */
  client function publish(file, name)(_evt) {
    if (Client.confirm(@i18n("Are you sure you want to publish the file '{name}'?")))
      FileTokenController.Async.publish(file, function {
        // Client side.
        case {success}: void
        case ~{failure}: Notifications.error(@i18n("Publication failure"), <>{failure.message}</>)
      })
  }

  client function sync(file, name)(_evt) {
    if (Client.confirm(@i18n("Are you sure you want to update the file '{name}'?")))
      FileTokenController.Async.sync(file, function {
        // Client side.
        case {success: parent}: load_directory(parent)
        case ~{failure}: Notifications.error(@i18n("Update failure"), <>{failure.message}</>)
      })
  }

  /** {2} Common operations. */

  client function rename(file)(_) { Common.rename(~{file}) }
  client function delete(file)(_) { Common.delete(~{file}) }
  client function move(file, name, previous) { Common.move(~{file}, name, {none}) }

  /** {2} Selection of the file security. */

  /**
   * Update the security class of a file.
   * @param labels list of existing file labels. As of now, only the security label
   *    are in there. This argument is ingored.
   */
  client function updateClass(tid, name, list(Label.Client.label) _labels)(_evt) {
    function action(_, result) {
      match (result) {
        case [security]:
          FSController.Async.set_security({file: tid}, security, function {
            // Client side.
            case {success: parent}: load_directory(parent)
            case ~{failure}: Notifications.error(@i18n("File security failure"), <>{failure.message}</>)
          })
        case []: Notifications.error(@i18n("File security failure"), <>{@i18n("you must select one security label")}</>)
        default: Notifications.error(@i18n("File security failure"), <>{@i18n("you can choose only one security label")}</>)
      }
    }
    LabelChooser.create({
      title: "Classify file {name} to...",
      immediate: true,
      custom: {class},
      callback: ~{action, text: "reclassify"},
      exclude: []
    })
  }

  /** {1} File encryption. */

  /**
   * Encrypt a file's content.
   * @param progress update a progress bar.
   */
  client function encrypt(tid, name, (int -> void) progress)(_evt) {
    FileTokenController.Async.getChunks(tid, function {
      // Client side.
      case ~{chunks, key, raw}:
        // Retrieve the user's secret key.
        UserView.SecretKey.prompt(key, @i18n("Please enter your password to encrypt this file."),
          function (secretKey) {
            match (secretKey) {
              case {some: secretKey}:
                totalChunks = List.length(chunks) // Number of chunks.
                // Number of bytes needed to encode the chunk number.
                totalBytes =
                  if (totalChunks < 256) 1
                  else if (totalChunks < 65536) 2
                  else if (totalChunks < 16777216) 3
                  else 4
                // Encrypt the chunks.
                // The nonce used for the encryption of each chunk result
                // from the concatenation of a common, random prefix, and
                // the chunk number.
                keyPair = TweetNacl.Box.keyPair()
                noncePrefix = TweetNacl.randomBytes(TweetNacl.Box.nonceLength-totalBytes)
                progress(0) // Initialize progress bar.
                chunks = List.map(function (chunk) {
                  log("encrypt: encrypting chunk {chunk.number} of {totalChunks}")
                  nonceSuffix = Uint8Array.ofInt(chunk.number)
                  nonce = Uint8Array.concat(noncePrefix, nonceSuffix)
                  data = Uint8Array.decodeBase64(chunk.data)
                  data = TweetNacl.Box.box(data, nonce, keyPair.publicKey, secretKey)
                  // The hash must be recomputed to correspond to the encrypted chunk.
                  sha = TweetNacl.hash(data) |> Uint8Array.encodeBase64
                  // Upload the chunk data, and advance the progress bar.
                  RawFile.Chunk.upload(sha, Uint8Array.encodeBase64(data))
                  progress(chunk.number*100/totalChunks) // Advance progress bar.
                  ~{sha, number: chunk.number, size: Uint8Array.length(data)}
                }, chunks)
                encryption = {
                  key: Uint8Array.encodeBase64(keyPair.publicKey),
                  nonce: Uint8Array.encodeBase64(noncePrefix) // Only the nonce prefix.
                }
                // Send the encrypted chunks back to the server.
                FileTokenController.encrypt(
                  tid, raw, chunks, encryption,
                  Uint8Array.encodeBase64(keyPair.secretKey)
                ) |> ignore
              default: log("encrypt: encryption cancelled")
            }
          }
        )

      case {missing}: warning("encrypt: missing content of file {tid}")
      case {encrypted}: log("encrypt: file {tid} is already encrypted")
      case ~{failure}: log("encrypt: failed: {failure.message}")
    })
  }

  /** {1} Refresh parts of the view. */

  /** Insert the directory contents into the view. */
  client function finish_directory(html) {
    #files_list = html
  }

  /**
   * Asynchronously fetch the contents of a directory, and upload them into the view.
   * This function can apply for team and user directories (not shared ones).
   */
  exposed @async function server_directory(option(Directory.id) dir, URN.t urn) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      finish_directory(<></>)
    else {
      team = match (urn.mode) { case {files: "teams"}: true; default: false }
      path = Option.map(Directory.get_path(_, true), dir) ? []
      select = if (team) {{teams}} else {{user}} // File selection.
      files = FileToken.list(state.key, dir, select, true)
      directories = Directory.list(state.key, dir, select)
      if (dir == none) SidebarView.refresh(state, urn)
      html = DirectoryView.build(state.key, path, directories, files, team, none, none)
      finish_directory(html)
    }
  }

  /** Load the contents of a directory into the view. */
  client function load_directory(option(Directory.id) dir) { server_directory(dir, URN.get()) }
  /** Same function, as an event handler. */
  client function init_directory(option(Directory.id) dir, _evt) { server_directory(dir, URN.get()) }

  /**
   * Refresh the side treeview. This function only needs to be called
   * when renaming, moving, deleting or creating a directory.
   */
  client function refresh_tree_view() {
    void
    // urn = URN.get()
    // team = match (urn.mode) { case {files: "teams"}: true; default: false }
    // if (not(team)) {
    //   nodes = Directory.build_nodes_with_root(state.key, [])
    //   client function callback(_, node) {
    //     text = Treeview.text(node)
    //     id = Treeview.identifier(node)
    //     id = Directory.idofs(id)
    //     path = Treeview.description(node)
    //     urn = URN.make({files: ""}, Path.parse(path))
    //     Content.update(urn, true)
    //   }
    //   Treeview.build_serialized(#file_tree, nodes, callback)
    //   Treeview.options(#file_tree, {expandIcon: "fa fa-lg fa-folder-o", collapseIcon: "fa fa-lg fa-folder-o"})
    // }
  }

  /** {1} View components. */

  // FIXME not used ?
  // protected function hoverize(mid, file, xhtml) {
  //   match (mimetype_to_doctype(file.mimetype)) {
  //   case { img }:
  //     <a href="/file/raw/{mid}/{file.id}/{file.name}" target="_blank" title="{file.name}">{xhtml}</a>
  //     |> Xhtml.add_attribute_unsafe("rel", "popover", _)
  //     |> Xhtml.add_attribute_unsafe("data-placement", "right", _)
  //     |> Xhtml.add_attribute_unsafe("data-title", "{file.name}", _)
  //     |> Xhtml.add_attribute_unsafe("data-content", "<img src='{FSController.reencode_content(file)}'/>", _)
  //     // |> Xhtml.add_attribute_unsafe("rel", "popover", _)
  //     // |> Xhtml.add_attribute_unsafe("data-placement", "right", _)
  //     // |> Xhtml.add_attribute_unsafe("data-title", "{file.name}", _)
  //     // |> Xhtml.add_attribute_unsafe("data-content", "<iframe id='frameDemo' src='/file/raw/{mid}/{file.id}/{file.name}'></iframe>", _)
  //   case { html }:
  //     <a href="/raw/{mid}/{file.id}/{file.name}" target="_blank" title="{file.name}">{xhtml}</a>
  //   case { txt }:
  //     <a href="/raw/{mid}/{file.id}/{file.name}" target="_blank" title="{file.name}">{xhtml}</a>
  //   case { pdf }:
  //     <a href="/raw/{mid}/{file.id}/{file.name}" target="_blank" title="{file.name}">{xhtml}</a>
  //   case { verbatim }: xhtml
  //   }
  // }

  // File

  client function select(FileToken.id tid, name, access, security, parent, labels, xfid, _) {
    Dom.remove_class(dollar("#files_list .active"), "active")
    activate = Dom.select_parent_one(Dom.select_parent_one(#{"file-{tid}"}))
    Dom.add_class(activate, "active")
    create_link = Common.share({file: tid})
    share_link = Common.shareWith({file: tid}, name, security, access)
    delete_link = delete(tid)
    rename_link = rename(tid)
    move_link = move(tid, name, parent)
    class_link = updateClass(tid, name, labels)
    encrypt_link = encrypt(tid, name, Utils.const(void))
    text_link_list =
      Utils.text_link("share-o", share_link, AppText.share()) <+>
      Utils.text_link("link", create_link, AppText.create_link()) <+>
      Utils.text_link("trash-o", delete_link, AppText.delete()) <+>
      Utils.text_link("pencil-square-o", rename_link, AppText.rename()) <+>
      Utils.text_link("mail-forward-o", move_link, AppText.move()) <+>
      Utils.text_link("flag-o", class_link, AppText.change_classification()) <+>
      Utils.text_link("lock-o", encrypt_link, @i18n("Encrypt"))
    icon_link_list =
      Utils.icon_link("share-o", share_link, AppText.share()) <+>
      Utils.icon_link("link", create_link, AppText.create_link()) <+>
      Utils.icon_link("trash-o", delete_link, AppText.delete()) <+>
      Utils.icon_link("pencil-square-o", rename_link, AppText.rename()) <+>
      Utils.icon_link("mail-forward-o", move_link, AppText.move()) <+>
      Utils.icon_link("flag-o", class_link, AppText.change_classification()) <+>
      Utils.icon_link("lock-o", encrypt_link, @i18n("Encrypt"))
    table_menu = match (xfid) {
      case {ufile:ufid}: <></>
      case {hfile:hfid}:
        <ul class="dropdown-menu">
          {text_link_list}
          { 
              <></>
          }
        </ul>
      }
    menu = match (xfid) {
      case {ufile:ufid}: <></>
      case {hfile:hfid}:
        <ul class="nav visible-lg visible-md pull-right">
          {text_link_list}
        </ul>
        <ul class="nav visible-sm pull-right">
          {icon_link_list}
        </ul>
        <ul class="nav visible-xs pull-left">
          <li>
            <a class="dropdown-toggle" data-toggle="dropdown"><b class="caret"/></a>
            <ul class="dropdown-menu" role="menu">
              {text_link_list}
            </ul>
          </li>
        </ul>
    }
    actions_bar =
      <div class="file-name pull-left"><i class="fa fa-file-o pull-left"></i> {name}</div> <+> menu
    #files_actions = actions_bar
    #context_menu_content = table_menu
  }

  /**
   * Build the file download view. The href is a 'download' URL:  the file will be downloaded and
   * not opened in a new tab.
   * @param file a raw file, that can be for example the active version of a file token.
   * @param name the name of the token (potentially different from the raw name).
   */
  server private function build_file(tid, raw, name) {
    date = raw.created
    fsize = raw.size
    fmimetype = raw.mimetype
    sanname = Uri.encode_string(name)
    sanid = Uri.encode_string("{raw.id}")
    <div>
      <span class="fa fa-2x fa-file-o {mimetype_to_icon(fmimetype)}"/>
      <h5>{name}</h5>
    </div>
    <h6>
      <span id="file-{tid}-uploaded"
          onready={Misc.insert_timer("file-{tid}-uploaded", date)}></span>
      ·
      <span class="file_size o-selectable">{Utils.print_size(fsize)}</span>
    </h6>
    <div><a class="btn btn-primary btn-large" href="/raw/download/{sanid}/{sanname}">{AppText.download()}</a></div>
  }

  function handles(id, name, access, security, parent, clabels, hfid) {
    [ {name:{mousedown}, value: {expr: select(id, name, access, security, parent, clabels, {hfile: hfid}, _)}} ]
  }

  /**
   * @param path composite path: id of the root directory, completed by a subpath.
   */
  protected function init_shared_topbar(Share.t share, Path.t path, _) {
    state = Login.get_state()
    path = Path.to_string(path)
    menu =
      if (state.key == share.owner)
        <li>
          <a class="dropdown-toggle" data-toggle="dropdown" href="#">
            <span class="fa fa-lg fa-gear"/> <span class="caret"></span>
          </a>
          <ul class="dropdown-menu">
            <li><a href="/files{path}">{AppText.show_in_my_files()}</a></li>
            <li>
              <a onclick={Common.unshare(share.link)}>
                <span class="fa fa-unlink"/>
                {AppText.unshare_link()}
              </a>
            </li>
          </ul>
        </li>
      else
        <></>
    #topbar = TopbarView.build_generic(
      <div class="collapse navbar-collapse" id="w-navbar-collapse">
        <div id="login" class="navbar-right form-inline">{
          Login.build(state)
        }</div>
        <ul class="nav navbar-nav navbar-right">
          {menu}
        </ul>
      </div>
    )
  }

  /**
   * Build the view of a shared file or directory.
   * This corresponds to paths of the form:  /share/{share link}/{path}
   * The path complement is added in the case of shared directories to identify the sub-directory.
   */
  private function build_shared_file(Login.state state, share, FileToken.t token, Path.t path) {
    security = File.get_security(token.file) ? Label.open.id
    spath = Option.map(Directory.get_path(_, true), token.dir) ? []
    fullpath = spath ++ path

    if (Label.KeySem.user_can_read_security(state.key, security) ||
        Option.map(Label.allows_internet, Label.get(security)) ? false)
      // FIXME: use an iframe ?
      match (RawFile.get_metadata(token.active)) {
        case {some: raw}:
          <div class="main-page o-center" onready={init_shared_topbar(share, fullpath, _)}>
            {build_file(token.id, raw, token.name.fullname)}
          </div>
        default:
          <>Missing file version</>
      }
    else
      <>{AppText.unauthorized()}</>
  }

  protected function build_shared(string link, Path.t path) {
    state = Login.get_state()
    match (Share.get(Share.string_to_link(link))) {
      case {none}: Content.non_existent_resource
      case {some:share}:
        match (share.src) {
          // Point to a file: path is accessory.
          case {file: tid}:
            match (FileToken.get(tid)) {
              case {none}: Content.non_existent_resource
              case {some: token}: build_shared_file(state, share, token, path)
            }
          case ~{dir}:
            spath = Directory.get_path(dir, true)
            log("Shared folder: {spath}")
            fullpath = spath ++ path
            name = Directory.get_name(dir) ? AppText.share()
            // Access item pointed to by subpath.
            match (Directory.get_from_path(share.owner, {some: dir}, path)) {
              case ~{dir}:
                files = FileToken.list(share.owner, dir, {user}, false)
                directories = Directory.list(share.owner, dir, {all})
                DirectoryView.breadcrumb({shared: ~{link: share.link, name, path}}) <+>
                <div id="files_list" class="pane-content" onready={init_shared_topbar(share, fullpath, _)}>
                  {DirectoryView.build(share.owner, fullpath, directories, files, false, some(share), {none})}
                </div>
              case {file: token}:
                build_shared_file(state, share, token, path)
              case {inexistent}:
                Content.non_existent_resource
            }
        }
    }
  }

  /** View elements. */

  private function build_actions() {
    <div id="files_actions" class="pane-actions"></div>
  }

  function create_folder_button() {
    <a data-toggle="modal" data-target="#modal_create_folder" class="btn btn-sm btn-default">
      <i class="fa fa-plus-circle-o"/> {AppText.new_folder()}
    </a>
  }

  function upload_button() {
    <a onclick={UploadView.show} class="btn btn-default">
      <i class="fa fa-share-o"/> {AppText.upload()}
    </a>
  }

  /**
   * Build the navbar, which includes:
   *  - breadcrumb (all modes)
   *  - folder creation button (only if private or shared by team)
   */
  function build_navbar(state, Directory.reference ref) {
    ac =
      match (ref) {
        case {shared: _}
        case {team: {id: {none} ...}}: <></>
        default: create_folder_button()
      }
    bc = DirectoryView.breadcrumb(ref)
    <>{bc}<div class="pull-right">{ac}</div></>
  }

  function build_navbar_tree(share_opt) {
    // nfb =
    //   (if (Option.is_none(share_opt)) {
    //           <a data-toggle="modal" data-target="#modal_create_folder" class="btn btn-default navbar-btn navbar-right">
    //             <i class="fa fa-plus"/> {AppText.new_folder()}
    //           </a>
    //          } else <></>)
    <><h3>{AppText.folders()}</h3></>
  }

  function build_treeview(nodes, share_opt, _) {
    client function callback(_, node) {
      text = Treeview.text(node)
      id = Treeview.identifier(node)
      id = Directory.idofs(id)
      path = Treeview.description(node)
      urn = URN.make({files: ""}, Path.parse(path))
      Content.update(urn, false)
    }
    Treeview.build_serialized(#file_tree, nodes, callback)
    Treeview.options(#file_tree, {expandIcon: "fa fa-lg fa-folder-o", collapseIcon: "fa fa-lg fa-folder-o"})
  }

  protected function build(Login.state state, string mode, Path.t path) {
    match (mode) {
      // Links view.
      case "links":
        view = ShareView.build(state)
        urn = URN.make({files: ""}, path)
        <div class="pane-lg">
          <div class="pane-heading">
            <h3>{AppText.links()}</h3>
          </div>
          {view}
        </div>

      // Shared directories.
      case "teams":
        match (path) {
          case [id|path]:
            // Identify the team first.
            match (Directory.get_owner(id)) {
              case {some: team}:
                // Check the directory's owner is a team (to prevent access to user directories)
                if (User.key_exists(team)) <>{AppText.non_existent_folder(path)}</>
                else
                  match (Directory.get_from_path(team, {some: id}, path)) {
                    case ~{dir}:
                      actions = build_actions()
                      navbar = build_navbar(state, {team: {id: {some: id}, ~path}})
                      uploadto = Option.map(function (dir) { {left: dir} }, dir) ? {right: []} // Destination of uploaded files.
                      create = DirectoryView.create_modal(dir)
                      upload = UploadView.modal(uploadto, Team.get_security(team) ? Label.open.id)
                      <div class="pane-lg">
                        <div class="pane-heading">{navbar}</div>
                        {actions}
                        <div class="pane-content" onready={init_directory(dir, _)}>
                          <div id="files_list"/>
                          <div id="context_menu_content"/>
                        </div>
                      </div> <+>
                      create <+> upload

                    default: <>{AppText.non_existent_folder(path)}</>
                  }
              default: <>{AppText.non_existent_folder(path)}</>
            }
          default:
            // No directory creation and file upload (ownership would be ambigous).
            navbar = build_navbar(state, {team: {id: none, path: []}})
            actions = build_actions()
            <div class="pane">
              <div class="navbar">{navbar}</div>
              {actions}
              <div class="pane-content" onready={init_directory(none, _)}>
                <div id="files_list"/>
                <div id="context_menu_content"/>
              </div>
            </div>
        }

      // Directory view.
      default:
        match (Directory.get_from_path(state.key, {none}, path)) {
          case ~{dir}:
            actions = build_actions()
            navbar = build_navbar(state, {files: path})
            upload = UploadView.modal({right: path}, Label.open.id)
            create = DirectoryView.create_modal(dir)
            <div class="pane-lg">
            <div class="pane-heading">{navbar}</div>
              {actions}
              <div class="pane-content" onready={init_directory(dir, _)}>
                <div id="files_list"/>
                <div id="context_menu_content"/>
              </div>
            </div> <+>
            create <+> upload
          default: <>{AppText.non_existent_folder(path)}</>
        }
    }
  }

  function new_folder_link() {
    <a data-toggle="modal" data-target="#modal_create_folder" class="sidebar-link">
      <i class="fa fa-folder-o"/> {AppText.new_folder()}
    </a>
  }

  /** File decryption. */
  client function decrypt(user, parameters, filename, mimetype, _evt) {
    UserView.SecretKey.prompt(user, @i18n("Please enter your password to access this resource."), function {
      case {some: secretKey}:
        // Some decoding.
        filePublicKey = Uint8Array.decodeBase64(parameters.filePublicKey)
        fileSecretKey = Uint8Array.decodeBase64(parameters.fileSecretKey)
        tokenNonce = Uint8Array.decodeBase64(parameters.tokenNonce)
        match (TweetNacl.Box.open(fileSecretKey, tokenNonce, filePublicKey, secretKey)) {
          case {some: fileSecretKey}:
            userPublicKey = Uint8Array.decodeBase64(parameters.userPublicKey)
            noncePrefix = Uint8Array.decodeBase64(parameters.fileNonce)
            totalChunks = List.length(parameters.chunks) // Number of chunks.
            // Number of bytes needed to encode the chunk number.
            totalBytes =
              if (totalChunks < 256) 1
              else if (totalChunks < 65536) 2
              else if (totalChunks < 16777216) 3
              else 4
            bytes = List.fold(function (chunk, bytes) {
              match (bytes) {
                case {some: bytes}:
                  log("decrypt: opening chunk {chunk.number} or {totalChunks}")
                  nonceSuffix = Uint8Array.ofInt(chunk.number)
                  nonce = Uint8Array.concat(noncePrefix, nonceSuffix)
                  data = Uint8Array.decodeBase64(chunk.data)
                  match (TweetNacl.Box.open(data, nonce, userPublicKey, fileSecretKey)) {
                    case {some: data}:
                      some(Uint8Array.concat(bytes, data))
                    default:
                      warning("decrypt: decryption failed")
                      none
                  }
                default: none
              }
            }, parameters.chunks, some(Uint8Array.ofInt(0)))
            match (bytes) {
              case {some: bytes}:
                filename = Uri.encode_string(filename)
                dump = Uint8Array.encodeBase64(bytes)
                dataUrl = "data:{mimetype};fileName={filename};base64,{dump}"
                Client.winopen(dataUrl, {_self}, [], true) |> ignore
                // TODO do something xith the bytes.
                void
              default:
                Notifications.error(@i18n("File error"), <>{@i18n("PEPS could not read this file.")}</>)
            }
          default:
            warning("decrypt: failed to decrypt the file secret key")
            Notifications.error(@i18n("File error"), <>{@i18n("PEPS could not read this file.")}</>)
        }
      default:
        Notifications.error(@i18n("File error"), <>{@i18n("PEPS could not read this file.")}</>)
    })
  }

  /**
   * Filter the result of a download and return the adequate resource.
   * NB: different resources are returned depending on the file encryption:
   *  - if the file is not encrypted, then its content is returned immediatly
   *  - else, the encrypted chunks are returned in an HTML window, and decrypted
   *    after the user inputs his password.
   */
  private function resource(user, file, errbuilder) {
    match (file) {
      // Success.
      case ~{file, download}:
        mimetype = if (file.mimetype == "text/html") "text/plain" else file.mimetype
        match (RawFile.getContent(file)) {
          case ~{bytes}:
            // Clear content, returned as a binary resource.
            resource = Resource.binary(bytes, mimetype)
            if (download)
              Resource.add_header(
                resource,
                {content_disposition : {attachment : file.name}}
              )
            else resource
          case ~{chunks, filePublicKey, userPublicKey, fileNonce ...}:
            // Encrypted content: find the secret key encoded for the user.
            match (FileToken.findEncryption(file.id, user)) {
              case {key: fileSecretKey, nonce: tokenNonce}:
                // All encryption parameters are present, build a minimal HTML page
                // prompting the user for its password.
                parameters = ~{
                  chunks, filePublicKey, userPublicKey, fileNonce,
                  fileSecretKey, tokenNonce
                }
                Resource.page(
                  file.name,
                  <div id="main" onready={decrypt(user, parameters, file.name, file.mimetype, _)}>
                  </div>
                )
              default:
                // Encryption Failure.
                Resource.binary(Binary.create(0), "text/plain")
            }
        }
      // Errors.
      case {inexistent}:
        Resource.error_page(AppText.Not_found(),
          errbuilder(AppText.inexistent_resource(), <></>, {error}),
          {wrong_address})
      case {unauthorized}:
        Resource.error_page(AppText.Not_Allowed(),
          errbuilder(AppText.not_allowed_resource(), <></>, {error}),
          {unauthorized})
      default:
        Resource.error_page(AppText.Bad_request(),
          errbuilder(AppText.invalid_request(), <></>, {error}),
          {bad_request})
    }
  }

  /**
   * Generate the resource for a downloaded file.
   * Accepts two kinds of URLs:
   *   - /download/{id}/{name} => download file.
   *   - /{id}/{name} => open in new window.
   * Check access rights before download (security class).
   */
  protected function download(string path, errbuilder) {
    state = Login.get_state()
    log("download: path={path} ; user={state.key}")
    rawparser = parser {
      case download="/download"? "/" id=Utils.base64_url_string "/" .*:
        id = if (String.contains(id, "%")) Uri.decode_string(id) else id
        id = RawFile.idofs(id)
        match (RawFile.get(id)) {
          case {some: file}:
            // Check access rights.
            security = File.get_security(file.file) ? Label.open.id
            if (not(Label.KeySem.user_can_read_security(state.key, security) ||
                    Option.map(Label.allows_internet, Label.get(security)) ? false))
              {unauthorized: void}
            else ~{file, download: Option.is_some(download)}
          default: {inexistent}
        }
      case .* : {inexistent}
    }
    file = Parser.parse(rawparser, path)
    resource(state.key, file, errbuilder)
  }

  /** {1} Construction of the side bar. */
  Sidebar.sign module Sidebar {
    /** Build the sidebar elements. */
    function build(state, options, mode) {
      view = options.view
      function onclick(mode, path, _evt) {
        urn = URN.make({files: mode}, path)
        Content.update(urn, false)
      }

      [
        { id: SidebarView.action_id, text: AppText.upload_file(), action: UploadView.show },
        { name: "documents", id: "documents",  icon: "files-o",    title: AppText.Documents(),     onclick: onclick("", [AppText.Documents()], _) },
        { name: "downloads", id: "downloads",  icon: "download-o", title: AppText.Downloads(),     onclick: onclick("", [AppText.Downloads()], _) },
        { name: "pictures",  id: "pictures",   icon: "photos-o",   title: AppText.Pictures(),      onclick: onclick("", [AppText.Pictures()], _) },
        { name: "shared",    id: "shared",     icon: "users-o",    title: @i18n("Shared with me"), onclick: onclick("", [AppText.shared()], _) },
        { name: "links",     id: "links",      icon: "link",       title: AppText.links(),         onclick: onclick("links", [], _) },
        { separator: AppText.Team_Folders(), button: none },
        { content: DirectoryView.list_teams(state, view) },
        //{ separator: AppText.Recent_files() }
      ]
    }

  } // END SIDEBAR

}

