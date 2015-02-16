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

/** Configuration of the functor. */
type TreeChooser.config = {
  Treeview.options icons,
  (User.key, list(string) -> string) builder
  // (void -> string) empty // Text when list is empty.
}

/** Configuration of the chooser. */
type TreeChooser.options = {
  option(User.key) user, // Overrides the active user.
  string title,
  list(string) excluded,
  // list(string) roots,
  (string -> void) action
  // string insert // Insertion point.
}

/**
 * Implementation of a generic tree chooser.
 * @param config configuration of the functor.
 */
module TreeChooser(TreeChooser.config config) {

  private function log(msg) { Log.notice("[TreeChooser]", msg) }
  private function debug(msg) { Log.debug("[TreeChooser]", msg) }
  private function error(msg) { Log.error("[TreeChooser]", msg) }

  /** {1} Callbacks. */

  /** Destroy the chooser after use. */
  client function destroy(string id, _evt) { Dom.remove(#{id}) }
  /** Hide the modal (which triggers the destruction). */
  client function hide(string id, _evt) { Modal.hide(#{id}) }

  /** Complete a selector with a window close. */
  function select(string id, (string -> void) action, _evt, Treeview.node node) {
    Treeview.identifier(node) |> action
    Dom.hide(#{id})
  }

  /** {1} Construction of the chooser. */

  /** Tree builder, called when the modal has been built. */
  client function build(string id, nodes, action, _evt) {
    Treeview.build_serialized(#{"{id}-tree"}, nodes, select(id, action, _, _))
    Treeview.options(#{"{id}-tree"}, config.icons)
  }

  /** Create the chooser modal. */
  exposed function create(TreeChooser.options options) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) void
    else {
      id = Dom.fresh_id()
      nodes = config.builder(options.user ? state.key, options.excluded)
      modal = Modal.make(
        id,
        <>{options.title}</>,
        <div id="{id}-tree" onready={build(id, nodes, options.action, _)}></div>,
        WB.Button.make(
          { button: <>{AppText.Cancel()}</>, callback: hide(id, _) },
          [{`default`}]
        ),
        { Modal.default_options with backdrop:false, static:false, keyboard:false }
      )
      insert(id, modal)
    }
  }

  /**
   * Insert the modal into the client document, and bind
   * modal close events.
   */
  private client function insert(id, modal) {
    #main += modal // PREPEND the modal so it appears behind other modals (e.g. file chooser).
    Dom.bind(#{id}, {custom: "hidden.bs.modal"}, destroy(id, _)) |> ignore
    Modal.show(#{id})
  }

} // END TREECHOOSER

/** TreeChooser instances. */

TeamChooser = TreeChooser({
  icons: {
    expandIcon: "fa fa-chevron-right",
    collapseIcon:"fa fa-chevron-down"
  },
  builder: Team.treeview
})

DirChooser = TreeChooser({
  icons: {
    expandIcon: "fa fa-folder-o",
    collapseIcon:"fa fa-folder-o"
  },
  builder: Directory.treeview
})
