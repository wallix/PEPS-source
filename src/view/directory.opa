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

/** Describe the multiple ways of refering to a directory. */
type Directory.reference =
	{Path.t files} or       											                // For the mode /files
	{{option(Directory.id) id, Path.t path} team} or              // For the mode /files:share
	{{Share.link link, string name, Path.t path} shared}          // For the mode /shared

module DirectoryView {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[DirectoryView]", msg) }

  /** {1} Line rendering. */

	/** Table line rendering. */
	module Line {
		private function render_column(Login.state state, Directory.t dir, Path.t path, option(Share.t) share, Table.column column) {
      match (column) {
        case {name: {inert}}:
          {xhtml:
            <div id="folder-{dir.id}" class="file-thumbnail o-selectable context"
                data-toggle="context" data-target="#context_menu_content">
              <span class="fa fa-lg fa-folder-o"/>
              <a id="{dir.id}-name" title="{dir.name}" class="folder o-selectable">{dir.name}</a>
            </div>}
        case {name: {immediate: onclick}}:
          cbid = Random.string(10)
          fullname = Path.fullname(path, dir.name)
          attachment = {directory: {id: dir.id, name: dir.name}}
          {xhtml:
            <div id="folder-{dir.id}" class="file-thumbnail o-selectable context"
                onclick={onclick(cbid, attachment,_)}
                data-toggle="context" data-target="#context_menu_content">
              <span id="{dir.id}-name" title="{fullname}" class="folder o-selectable">{fullname}</span>
            </div>}
        case {name: ~{link}}:
          urn =
            match (link) {
              case {team}:
                URN.make({files: "teams"}, [Utils.base64_url_encode(dir.id)])
              case {shared}
              case {personal}:
                Directory.urn(path ++ [dir.name], share)
            }
          update = Content.update_callback(urn, _)
          {xhtml:
            <div id="folder-{dir.id}" class="file-thumbnail folder_block o-selectable context"
                data-toggle="context" data-target="#context_menu_content">
              <i class="fa fa-folder-o"/>
            </div>
            <a id="{dir.id}-name" title="{dir.name}" onclick={update} class="folder o-selectable">{dir.name}</a>}
        case {created}: {xhtml: <span class="file_uploaded o-selectable"></span>}
        case {edited}: {xhtml: <span class="file_edited o-selectable"></span>}
        case {owner: {team}}: {xhtml: <></>}
        case {owner: {user}}: {xhtml: <></>}
        case {origin}: {xhtml: <></>}
        case {size}:
          { xhtml: <span class="file_size o-selectable"></span>,
            decorator: Xhtml.add_attribute_unsafe("data-size", "0", _) }
        case {mimetype}: {xhtml: <span class="file_kind o-selectable">{@intl("folder")}</span>}
        case {class}: {xhtml: <span class="file_labels o-selectable"></span>}
        case {link}: {xhtml: ShareView.make_link(dir, share)}
        case {checkbox: onclick}:
          cbid = Random.string(10)
          attachment = {directory: {id: dir.id, name: dir.name}}
          {xhtml: <span><input type="checkbox" id="fccb_{cbid}" onclick={onclick(cbid,attachment,_)}></input></span>}
      }
    }

    function WBootstrap.Table.line render(Directory.t dir, option(Share.t) share, handles, Table.line line) {
      state = Login.get_state()
      path = Directory.get_path(dir.id, false)
      Table.render(
        render_column(state, dir, path, share, _),
        handles(dir.id, dir.name, dir.parent, []), // FIXME
        line
      )
    }
	} // END LINE

	/** {1} Callbacks. */

	/** {2} Folder creation. */

  client function create(option(Directory.id) parent, _) {
    name = Dom.get_value(#name_input) |> String.trim
    Modal.hide(#modal_create_folder) |> ignore
    log("create: creating folder [{parent}]/{name}...")
    // Asynchrnous server call.
    DirectoryController.Async.create(parent, name, function {
      // Client side.
      case {success}:
        FileView.load_directory(parent)
        FileView.refresh_tree_view()
      case ~{failure}:
        Notifications.error(@intl("Folder creation failure"), <>{failure.message}</>)
    })
  }

  /**
   * Create a modal which inputs the name of the new folder.
   * the new folder will have for parent the argument given to the modal.
   * at the moment of its creation.
   */
  function create_modal(parent) {
    create_action = create(parent, _)
    Modal.make("modal_create_folder", <>{AppText.new_folder()}</>,
      Form.wrapper(
        <div class="form-group">
          <div class="frow">
            <label for="name_input" class="control-label fcol">{@intl("Name")}:</label>
            <div id="name_input-form-group" class="fcol fcol-lg">
              <input id="name_input" type="text" class="form-control" value="" onnewline={create_action}/>
            </div>
          </div>
        </div>
      , true),
      WB.Button.make({button: <>{AppText.create()}</>, callback: @public_env(create_action)}, [{primary}]),
      { Modal.default_options with
        backdrop: false,
        static: false,
        keyboard: true }
    )
  }

  /** {2} Common operations. */

  client function rename(dir)(_) { FileView.Common.rename(~{dir}) }
  client function delete(dir)(_) { FileView.Common.delete(~{dir}) }
  // Parent team is useless here, but we want to eliminate the directory itself in
  // the list of possible destinations.
  client function move(dir, name, _previous) { FileView.Common.move(~{dir}, name, {some: dir}) }

  /** {2} Others. */

	/** Handles associated with table directoru lines. */
  function handles(id, name, parent, path) {
    [ { name: {click}, value: {expr: @public_env(select(id, name, parent, _))} } ]
      // { name: {dblclick},
      //   value: {expr: function(_e) { Content.update(URN.make({files: ""}, path), false) }} } ]
  }


   client function select(Directory.id dir, name, parent, _) {
    Dom.remove_class(dollar("#files_list .active"), "active");
    activate = Dom.select_parent_one(Dom.select_parent_one(#{"folder-{dir}"}))
    Dom.add_class(activate, "active");
    create_link = FileView.Common.share(~{dir})
    share_link = FileView.Common.shareWith(~{dir}, name, 1, {admin}) // 1 is open security class.
    delete_link = delete(dir)
    rename_link = rename(dir)
    move_link = move(dir, name, parent)
    text_link_list =
      Utils.text_link("share-o", share_link, AppText.share()) <+>
      Utils.text_link("link", create_link, AppText.create_link()) <+>
      Utils.text_link("trash-o", delete_link, AppText.delete()) <+>
      Utils.text_link("pencil-square-o", rename_link, AppText.rename()) <+>
      Utils.text_link("mail-forward-o", move_link, AppText.move())
    icon_link_list =
      Utils.icon_link("share-o", share_link, AppText.share()) <+>
      Utils.icon_link("link", create_link, AppText.create_link()) <+>
      Utils.icon_link("trash-o", delete_link, AppText.delete()) <+>
      Utils.icon_link("pencil-square-o", rename_link, AppText.rename()) <+>
      Utils.icon_link("mail-forward-o", move_link, AppText.move())
    table_menu =
      <ul class="dropdown-menu">
        {text_link_list}
      </ul>
    menu =
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
    actions_bar =
      <div class="file-name pull-left"><i class="fa fa-folder-o pull-left"></i> {name}</div> <+> menu
    #files_actions = actions_bar
    #context_menu_content = table_menu
  }

  /**
   * Core function of the file view. Build the file and directory table.
   * @param isteam true iff the mode is files:share
   * @param share is some iff the active directory is accessed through a public link.
   *
   * TODO: isteam and share cannot be both active at the same time: merge them into a common type.
   */
  server function build(User.key key, Path.t path, directories, files, isteam, option(Share.t) share, option(list(FileToken.snippet)) search_files_opt) {
    t0 = Date.now()
    // Conditions to display the 'shared by' and 'link' columns.
    has_shared = List.exists(FileToken.is_shared, files)
    has_link = List.exists(FileToken.has_link, files) || List.exists(Directory.has_link, directories)
    link =
      if (isteam) {link: {team}}
      else if (Option.is_some(share)) {link: {shared}}
      else {link: {personal}}
    // Columns in reverse order.
    cshared = if (has_shared) [{origin}] else []
    clink = if (has_link) [{link}] else []
    line = clink ++ [{class}, {edited}, {mimetype}, {size}] ++ cshared ++ [{name: link}]
    renderers = {
      file: FileView.Line.render(_, path, share, FileView.handles, _),
      directory: DirectoryView.Line.render(_, share, DirectoryView.handles, _)
    }
    content =
      match (search_files_opt) {
        case {some:search_files}:
          { files: List.filter_map(function(file) { FileToken.get(file.id) }, search_files), directories: [] }
        case {none}:
          ~{files, directories}
      }
    t1 = Date.now()
    table = Table.build(content, renderers, line)


    table
  }

  /** Build a breadcrumb adapted to the given directory reference. */
  protected function breadcrumb(Directory.reference ref) {
  	function item(urn, name) {{
  		custom_li :
        <li class="active">
          <a onclick={Content.update_callback(urn, _)}>
          <span class="fa fa-lg fa-folder-o"/> {name} </a>
        </li>
    }}
  	items =
  		match (ref) {
  			case {files: path}:
  				List.fold_map(function (name, acc) {
  					urn = URN.make({files: ""}, List.rev([name|acc]))
  					(item(urn, name), [name|acc])
  				}, path, []).f1
  			case {shared: ~{link, path ...}}:
  				List.fold_map(function (name, acc) {
  					urn = URN.make({share: link}, List.rev([name|acc]))
  					(item(urn, name), [name|acc])
  				}, path, []).f1
  			case {team: {id: {some: id}, ~path}}:
  				Directory.get_full_path(id, true) |>
          List.map(function (dir) {
            urn = URN.make({files: "teams"}, [dir.id])
            item(urn, dir.name)
          }, _)
	      default: []
  		}
  	root =
  		match (ref) {
  			case {files: _}: {custom_li : <li><a onclick={Content.update_callback(URN.make({files: ""}, []), _)}>{AppText.files()} </a></li>}
  			case {shared: ~{link, name ...}}: {custom_li : <li><a onclick={Content.update_callback(URN.make({share: link}, []), _)}>{name} </a></li>}
  			case {team: _}: {custom_li : <li><a onclick={Content.update_callback(URN.make({files: "teams"}, []), _)}>Teams </a></li>}
  		}
  	<>
    <div id="search_notice" onready={function (_) { Dom.hide(#search_notice) }}>{"{AppText.search()}:"}</div>
    <div id="files_breadcrumb" class="pull-left">
      { WBootstrap.Navigation.breadcrumb([root | items], <>/</>) }
    </div>
    </>
  }

  /** For the sidebar: list the root team directories. */
  function list_teams(Login.state state, view) {
    if (not(Login.is_logged(state))) <></>
    else {
      directories = Directory.list(state.key, none, {teams})
      list =
        List.rev_map(function (dir) {
          urn = URN.make({files: "teams"}, [dir.id])
          onclick = Content.update_callback(urn, _)
          <dt class="sidebar-menu-item"><a class="name" onclick={onclick}>
            <i class="fa fa-folder-o"></i> {dir.name}</a></dt>
        }, directories)

      match (view) {
        case {icons}:
          <>{ List.fold(`<+>`, list, <dl></dl>) }</>
        case {folders}:
          <>
            { List.fold(`<+>`, list, <dl></dl>) }
          </>
        default: <>{AppText.error()}: {@intl("view case not possible")} {view}</>
      }
    }
  }

}
