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

type AttachedRef.attachment = {
  string name,
  File.id id,              // A File id (newly uploaded files generate a raw file and an associated file).
  File.origin origin       // Shared means the file is in the db, upload means the file has just been created.
}

/** Type of selected objects. TODO remove. */
type FileRef.selected =
    { { File.id id, string name, int size, string mimetype } file }
 or { { Directory.id id, string name } directory }


type AttachedRef.attachments = list(AttachedRef.attachment)

/**
 * The reference contains a map with two keys:
 *  - the id of the upload view
 *  - the hash of the file in this view.
 */
client attached_ref = ClientReference.create(map((string, string), AttachedRef.attachment) Map.empty)

client module AttachedRef {
  function set(id, hash, elt) { ClientReference.update(attached_ref, Map.add((id, hash), elt, _)) }
  function remove(id, hash)   { ClientReference.update(attached_ref, Map.remove((id, hash), _)) }
  function mem(id, hash)      { ClientReference.get(attached_ref) |> Map.mem((id, hash), _) }

  function clear(id)          { ClientReference.update(attached_ref, Map.filter(function ((kid, _), _) { kid != id }, _)) }
  function list(id)           { ClientReference.get(attached_ref) |> Map.fold(function ((kid, _), elt, acc) { if (id == kid) [elt|acc] else acc }, _, []) }
  function is_empty(id)       { ClientReference.get(attached_ref) |> Map.exists(function ((kid, _), _) { kid == id }, _) |> not }
}

module UploadView {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[UploadView]", msg) }
  private function debug(msg) { Log.debug("[UploadView]", msg) }
  private function warning(msg) { Log.warning("[UploadView]", msg) }

  /** {1} View components. */

  /** Build the icon of a file attachment, to be inserted in the drop zone. */
  client function fileicon(upid, id, name, size, option(ResumableFile.t) file) {
    thumbsize = AppConfig.thumbsize
    (icon, canvas) =
      match (file) {
        // Uploading file.
        case {some: file}:
          if (String.has_prefix("image", file.file.`type`))
           (<img id="{id}-icon"></img>,
            <canvas id="{id}-canvas" height={thumbsize} width={thumbsize} hidden></canvas>)
          else (<i class="fa fa-file-o"/>, <></>)
        // Local file: fetch preview.
        default:
          match (FileController.get_thumbnail(File.idofs(id))) {
            case {some: (_raw, dataUrl)}: (<img src={dataUrl}/>, <></>)
            default: (<i class="fa fa-file-o"/>, <></>)
          }
      }
    progress =
     (if (Option.is_some(file)) <progress id="{id}-progress" value="0"></progress>
      else <></>)
    <div id={id} class="file-attached pull-left fade in">
      <div class="file-thumbnail pull-left">{icon}</div>
      <div class="file-attached-content">
        <div class="name">{Utils.string_limit(35, name)}</div>
        <small class="size">{Utils.print_size(size)}</small>
      </div>
      <a class="fa fa-times file_action" onclick={function (_evt) { remove(upid, id, file) }}></a>
      {canvas}
      {progress}
    </div>
  }

  /** {1} Actions. */

  /** Remove files from the file upload selector. */
  client function remove(upid, id, option(ResumableFile.t) file) {
    AttachedRef.remove(upid, id) // Remove from local reference.
    Dom.remove(#{id}) // Remove from view.
    if (AttachedRef.is_empty(upid)) {
      Dom.hide(#{"{upid}-files"})
      Dom.set_attribute_unsafe(#upload_button, "disabled", "disabled")
    }
    match (file) {
      case {some: file}:
        debug("remove: {file.fileName}")
        file.cancel() // Cancel upload.
        FSController.purge(RawFile.idofs(file.uniqueIdentifier)) |> ignore // Remove partial file in memory.
      default:
        void
    }
  }

  /**
   * Clear a file selection.
   * Should running uploads be cancelled ?
   */
  client function clear(upid) {
    AttachedRef.clear(upid)
    #{"{upid}-files"} = <></>
    Dom.hide(#{"{upid}-files"})
    Button.button(#upload_button, "complete")
  }

  /** {1} Resumable. */

  /** File insertion: insert file into the view only (added to reference as soon as upload is finished). */
  client function fileAdded(string upid)(ResumableFile.t file) {
    name = file.fileName
    size = file.size
    id = file.uniqueIdentifier
    debug("fileAdded: {name} {size} {id}")

    Dom.show(#{"{upid}-files"})
    #{"{upid}-files"} += fileicon(upid, id, name, size, some(file)) // Add to view.
    Resumable.File.preview("{id}-canvas", "{id}-icon", file.file) // Create preview.
    Dom.set_attribute_unsafe(#upload_button, "disabled", "disabled") // Disable upload button.
    file.resumableObj.upload() // Start upload.
  }
  /**
   * File error: cancel the upload.
   * TODO: add a retry option.
   */
  client function fileError(string upid)(ResumableFile.t file, string message) {
    warning("fileError: {message}")
    remove(upid, file.uniqueIdentifier, some(file))
  }
  /** File progress: upload the file's progress bar. TODO */
  client function fileProgress(ResumableFile.t file) {
    debug("fileProgress: {file.fileName} {file.progress(false)}")
    Dom.set_value(#{"{file.uniqueIdentifier}-progress"}, "{file.progress(false)}")
  }
  /** File complete: create file and insert into reference. TODO */
  client function fileSuccess(string upid)(ResumableFile.t file) {
    debug("fileSuccess: {file.fileName}")
    id = file.uniqueIdentifier
    match (FSController.file_of_raw(RawFile.idofs(id))) {
      case {success: fid}:
        log("fileSuccess: sending preview...")
        Resumable.File.sendPreview("{id}-canvas", "image/png", id, "/thumbnail") // Send preview (if defined).
        AttachedRef.set(upid, id, { name: file.fileName, id: fid, origin: {upload} }) // Add to reference.
        Dom.remove(#{"{id}-progress"})
      case {failure: msg}:
        debug("fileSuccess: failed to convert a raw file into a file")
        remove(upid, id, some(file))
    }
  }
  /** All files uploaded: enable the upload button. */
  client function complete() { Dom.remove_attribute(#upload_button, "disabled") }

  /** Create and set up a resumable object. */
  client function init_resumable(string upid, string dropzone, string upload)(_evt) {
    options = {
      Resumable.defaults with target: "/upload",
      testChunks: true, method: "octet",
      maxChunkRetries: some(3),
      randomIdentifier: true,
      withChunkSha: true
    }
    resumable = Resumable.create(options)
    // Bind dom elements.
    Resumable.assignDrop(resumable, dropzone)
    Resumable.assignBrowse(resumable, upload)
    // Bind upload events.
    Resumable.Bind.complete(resumable, complete)
    Resumable.Bind.fileError(resumable, fileError(upid))
    Resumable.Bind.fileAdded(resumable, fileAdded(upid))
    Resumable.Bind.fileProgress(resumable, fileProgress)
    Resumable.Bind.fileSuccess(resumable, fileSuccess(upid))
  }

  /** {1} Local selection. */

  /** For the compose modal: select files from the cloud. */
  function select(upid, _evt) {
    selected = List.map(_.id, AttachedRef.list(upid)) // exclude current selection.
    FileChooser.create({
      title: AppText.choose_file(),
      immediate: false,
      callback: {action: do_select(upid, _, _), text: AppText.attach() },
      exclude: selected, custom
    })
  }
  /** Callback of the {attach} function. */
  client function do_select(id, User.key key, selected) {
    List.iter(function (fid) {
      match (FileController.get_attachment(fid)) {
        case {some: attach}: insert(id, key, {file: attach}, true) |> ignore
        default: void
      }
    }, selected)
  }
  /**
   * Add selected files to the dom element {upid}-files.
   * @param setview whether to modify the view.
   */
  client function insert(upid, key, FileRef.selected attached, bool setview) {
    match (attached) {
      case ~{file}:
        id = File.sofid(file.id)
        if (not(AttachedRef.mem(upid, id))) {
          name = file.name
          AttachedRef.set(upid, id, { ~name, id: file.id, origin: {shared: key} })
          icon = fileicon(upid, id, name, file.size, none)
          if (setview) {
            Dom.show(#{"{upid}-files"})
            #{"{upid}-files"} += icon
          }
          icon
        } else
          <></>
      case ~{directory}:
        // TODO attach folders
        <></>
    }
  }

  /** Extract the information specific to file attachments. */
  private exposed function process_attachments(list(File.id) files) {
    state = Login.get_state()
    files = List.filter_map(function (fid) {
      match (File.get_raw(fid)) {
        case {none}: {none}
        case {some: raw}:
          upfile = {
            name: raw.name,
            size: raw.size,
            mimetype: raw.mimetype,
            id: fid
          }
          {some: {file: upfile}}
      }
    }, files)
    (state.key, files)
  }

  /**
   * Upload zone of the compose modal.
   * @param files initial setting of the upload element.
   */
  function attachment_box(Login.state state, string id, list(File.id) files) {
    // Set up the attachment reference.
    // AttachedRef.clear(id)
    (key, files) = process_attachments(files)
    files_html = List.fold(function (file, acc) { acc <+> insert(id, key, file, false) }, files, <></>)
    style = if (files == []) "display: none;" else ""
    // Html of the upload element.
    <div class="form-group attachments" id="{id}-attachments" onready={init_resumable(id, "{id}-attachments", "{id}-fileupload")}>
      <div class="frow">
        <label class="control-label fcol">
          <i class="fcol fa fa-paperclip"></i><span class="fcol">{AppText.Attachments()}:</span>
        </label>
        <div class="fcol fcol-lg">
          <div class="pull-right">
            <a class="btn btn-sm dropdown-toggle"
                onclick={select(id, _)}>
              <span class="fa fa-files-o"></span>{AppText.choose_from_files()}
            </a>
            <span class="separator"/>
            <a class="btn btn-sm fileinput-button">
              <span class="fa fa-share-o"></span> {AppText.upload()}
              <input id="{id}-fileupload" type="file" multiple name="files[]" data-url="/upload"/>
            </a>
          </div>
        </div>
      </div>
    </div>
    <div id="{id}-files" class="files form-group" style="{style}">{files_html}</div>
  }



  /** {1} Uploads. */

  /** Upload buttons of the upload modal. */
  server function upload_buttons(where) {
    <div class="pull-right">
      { WB.Button.make(
          { button: <>{AppText.upload()}</>,
            callback: FileView.upload(where, _) },
          [{primary}]) |>
        Utils.data_loading_text(AppText.Uploading(), _) |>
        Utils.data_complete_text(AppText.upload(), _) |>
        Xhtml.add_id(some("upload_button"), _) |>
        Xhtml.set_attribute_unsafe("disabled", "disabled", _) }
    </div>
  }

  @expand protected function selectors(User.key key, Label.id security) {
    <div>
      <div class="files-upload-group pull-left">
        <label class="control-label">{AppText.classification()}: </label>
        {LabelView.Class.selector("file_class", key, security)}
        <div class="btn btn-default fileinput-button" onready={init_resumable("upload", "modal_upload", "fileupload")}>
            {AppText.Select_file()}
            <input id="fileupload" type="file" name="files[]" data-url="/upload" multiple/>
        </div>
      </div>
    </div>
  }

  server upload_table =
    <div id=#upload_table role="presentation" class="files form-group">
      <div id="upload-files"></div>
    </div>

  /**
   * Build the upload modal.
   * @param where destination of uploaded files.
   * @param security default security label applied to uploaded files.
   */
  function modal(either(Directory.id, Path.t) where, Label.id security) {
    t0 = Date.now()
    state = Login.get_state()
    name =
      match (where) {
        case {right: []}: AppText.files()
        case {right: path}: Utils.last(path)
        // Note: if the directory is non existent, the files are uploaded to the root anyway
        // AppText.files is a correct alternative.
        case {left: dir}: Directory.get_name(dir) ? AppText.files()
      }
    t1 = Date.now()
    selectors = selectors(state.key, security)
    t2 = Date.now()
    buttons = upload_buttons(where)
    t3 = Date.now()
    modal = Modal.make(
      "modal_upload",
      <>{AppText.upload()} to '{name}'</>,
      <form role="form" class="form-horizontal"><div class="form-group"><p class="form-control-static">{AppText.upload_help()}</p></div>{upload_table}</form>,
      selectors <+> buttons,
      { Modal.default_options with
        backdrop: false,
        static: false,
        keyboard: true }
    )


    modal
    // TODO: bind the clearing function to the close event.
    // Dom.bind(#{id}, {custom= "hidden.bs.modal"}, destroy(id, init.mid, _)) |> ignore
  }

  /** Display the file upload modal window. */
  client function show(_) {
    Modal.show(#modal_upload)
  }

}
