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


/** Selection callback. */
type Chooser.callback('id) = {
  (User.key, list('id) -> void) action,
  string text
}

/** Configuration of the chooser, upon calling {Chooser.create}. */
type Chooser.options('id, 'custom) = {
  string title,
  bool immediate,
  'custom custom,                              // To pass specific instructions.
  list('id) exclude,
  Chooser.callback('id) callback
}

/** Internal configuration of the chooser. */
type Chooser.settings('id, 'filter, 'custom) = {
  string id,                                  // Id of the chooser.
  bool immediate,                             // Action is triggered by clicking on elements.
  'custom custom,
  User.key user,                              // Active user.
  list('id) exclude,                          // Elements excluded from the selection.
  (User.key, list('id) -> void) onclick,      // Selection callback.
  'filter filter                              // User filter, defined by user input.
}

/** Results. */
type Chooser.page('ref, 'item) = {
  int size, bool more,
  'ref first, 'ref last,
  list('item) elts
}

/** Functor arguments. */
type Chooser.setup('ref, 'id, 'filter, 'item, 'custom) = {
  'ref initRef,
  string listClass, // Additional class to add to the element list.
  'filter emptyFilter,
  (string -> 'filter) parseFilter,
  (string -> 'id) parseId,
  (Login.state, 'ref, Chooser.settings('id, 'filter, 'custom) -> Chooser.page('ref, 'item)) fetchItems,
  ('item, ('id, Dom.event -> void) -> xhtml) buildItem
}

/** Generic element chooser. */
module Chooser(Chooser.setup('ref, 'id, 'filter, 'item, 'custom) setup) {

  /** {1} Page scrolling. */

  /**
   * Fetched pre-formatted user snippets from the database, ready for
   * insertion in the view. The asynchronous status ensures that the list scroll
   * remains fluid.
   */
  private exposed @async function void fetch(ref, settings) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      append(settings, Xhtml.precompile(<>{AppText.login_please()}</>), ref, 0)
    else {
      t0 = Date.now()
      page = setup.fetchItems(state, ref, settings)


      pagehtml = buildItems(page, settings) |> Xhtml.precompile
      append(settings, pagehtml, page.last, page.size)
    }
  }

  /**
   * Insert the loaded elements into the view.
   * If more elements are to be expected, then restore the {scroll} handler, with updated
   * parameters (set to fetch the following elements).
   */
  private client function append(settings, xhtml html, ref, int size) {
    if (size > 0) {
      #{"{settings.id}-list"} += html                        // Append new elements to the end of the list.
      Dom.bind(#{"{settings.id}-list"}, {scroll}, scroll(settings, ref, _)) |> ignore
    }
  }

  /**
   * Load more elements, and append them to the end of the list.
   * Called exclusively by the function {scroll}, which detects the optimal moment for loading more elements.
   * This function must NOT be async: we need to deactivate the {scroll} event handler, to avoid duplicate
   * calls to {fetch}. {fetch} IS asynchronous, and this ensures the fluidity of the scroll.
   */
  private client function void load(settings, ref) {
    // log("load: from:{ref}")
    Dom.unbind_event(#{"{settings.id}-list"}, {scroll})           // Unbind event to avoid multiple requests.
    fetch(ref, settings)                                          // Send request for more elements.
  }

  /**
   * Called on scroll events. Detect when less than a certain amount of elements remain in the list
   * to know when to trigger the function to fetch more user.
   * User height is estimated at 80px for the purpose of determining the number of elements left in the list.
   * When less than three times the amount of visible user remain in the list, new elements are fetched.
   * Same as {load}, this function needn't be asynchronous.
   */
  private client function void scroll(settings, ref, _evt) {
    list = #{"{settings.id}-list"}
    full = Dom.get_scrollable_size(list).y_px
    current = Dom.get_scroll_top(list)
    height = Dom.get_height(list)
    mvisible = height/80
    mleft = (full-current)/80 - mvisible  // Number of messages left in the list to scroll for.
    if (mleft < 3*mvisible) load(settings, ref)
  }

  /** Generate a client callbacks from the settings, to be added to items. */
  private client function callback(settings, id, _evt) {
    settings.onclick(settings.user, [id]) |> ignore
    Modal.hide(#{settings.id}) |> ignore // Release the modal.
  }
  private client function activate(id, _evt) { Dom.toggle_class(#{"{id}"}, "list-group-item-selected") }


  /** {1} Build user list group. */

  /** Build a list of user items. */
  private server function buildItems(page, settings) {
    t0 = Date.now()
    callback =
      if (settings.immediate) callback(settings, _, _)
      else activate
    list = List.fold(function (user, list) {
      setup.buildItem(user, callback) <+> list
    }, page.elts, <></>)


    list
  }

  /** Extract the list of selected elements. */
  private client function extract(string id) {
    items = Dom.select_inside(#{id}, Dom.select_class("list-group-item-selected"))
    Dom.fold(function (item, acc) { [Dom.get_id(item)|acc] }, [], items)
  }

  /** {1} Construction. */

  /** Create a new user chooser modal, and insert it in the document. */
  exposed function create(Chooser.options('id, 'custom) options) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) void
    else {
      id = Dom.fresh_id()
      settings = Chooser.settings('id, 'filter, 'custom) ~{
        id, filter: setup.emptyFilter,
        custom: options.custom,
        immediate: options.immediate,
        user: state.key,
        onclick: options.callback.action,
        exclude: options.exclude
      }
      search =
        <div class="chooser-filter">
          <input id="{id}-input" type="text" class="form-control" placeholder="{AppText.filter()}" autocomplete="off" value=""
              onnewline={reset(settings, _)}/>
        </div>
      modal = Modal.make(id,
        <>{options.title}</>,
        <div class="chooser-modal">
          <div id="{id}-header">{search}</div>
          <div class="chooser-content {setup.listClass}" onready={function (_) { load(settings, setup.initRef) }}>
            <ul class="list-group" id="{id}-list"></ul>
          </div>
        </div>,
        buttons(id, state.key, options),
        { Modal.default_options with backdrop:false, static:false, keyboard:false }
      )
      insert(id, modal)
    }
  }

  private client function insert(string id, xhtml modal) {
    Log.notice("[Chooser]", "inserting modal {id}")
    #main =+ modal // APPPEND the modal so it appears in front of other modals (e.g. compose modals).
    initscript =
      <script id="{id}-init" type="text/javascript">
        {Xhtml.of_string_unsafe("init_chooser('#{id}');")}
      </script>
    #{id} += initscript // NB: must be upload AFTER the modal, else the script can not be executed correctly.
    Modal.show(#{id})
    Dom.bind(#{id}, {custom: "hidden.bs.modal"}, destroy(id, _)) |> ignore
  }

  /** Modal button bar. */
  private function xhtml buttons(string id, User.key user, Chooser.options('id, 'custom) options) {
    cancel = WB.Button.make({button: <>Cancel</>, callback: cancel(id, _)}, [{`default`}])
    action = WB.Button.make({button: <>{options.callback.text}</>, callback: select(id, user, options.callback.action, _)}, [{primary}])

    if (options.immediate) cancel
    else cancel <+> action
  }

  /** {1} Callbacks. */

  /** Triggered by query value changed. */
  private client function reset(settings, _) {
    value = Dom.get_value(#{"{settings.id}-input"}) |> String.trim
    #{"{settings.id}-list"} = <></>
    load({settings with filter: setup.parseFilter(value)}, setup.initRef)
  }

  /**
   * Called when clicking on 'Attach'. Parse and return the selected elements.
   * Closes the modal after sending the results.
   */
  private client function select(string id, User.key user, callback, _) {
    elts = extract(id) |> List.map(setup.parseId, _)
    callback(user, elts) |> ignore
    Modal.hide(#{id}) |> ignore
  }

  /** Called after cancel action: close the modal. */
  private client function cancel(string id, _) { Modal.hide(#{id}) |> ignore }

  /** Toggle the search view. */
  private client function toggle(id, _) { Dom.transition(#{id}, Dom.Effect.toggle()) |> ignore }

  /** Destroy a modal. */
  private client function destroy(id, Dom.event _evt) { Dom.remove(#{id}) }

} // END CHOOSER


type UserChooser.setup = Chooser.setup(User.fullname, User.key, User.filter, User.profile, Label.id)
exposed UserChooser = Chooser(UserChooser.setup {
  initRef: {lname: "", fname: ""},
  listClass: "users_list",
  emptyFilter: User.emptyFilter,
  parseFilter: function (value) { {name: value, level: 0, teams: []} },
  parseId: identity,
  fetchItems: function (state, ref, settings) {
    User.fetch(
      ref, AppConfig.pagesize, settings.custom,
      settings.filter, settings.exclude
    ) |>
    UserController.highlight |> Iter.to_list |>
    UserController.page
  },
  buildItem: function (user, onclick) {
    avatar = UserView.userimg(user.picture, Utils.voidaction)
    email = Email.to_name(user.email)
    teams = List.map(Team.get_name, user.teams) |> Misc.spanlist("teams", _)
    <a class="list-group-item" id="{user.key}" onclick={onclick(user.key, _)}>
      {avatar}
      <div class="user">
        {email}{teams}
      </div>
    </a>
  }
})

type FileChooser.setup = Chooser.setup(string, File.id, FileToken.filter, FileToken.t, void)
exposed FileChooser = Chooser(FileChooser.setup {
  initRef: "",
  listClass: "",
  emptyFilter: FileToken.emptyFilter,
  parseFilter: FileToken.parseFilter,
  parseId: File.idofs,
  fetchItems: function (state, ref, settings) {
    FileTokenController.fetch(state.key, ref, AppConfig.pagesize, settings.filter, settings.exclude)
  },
  buildItem: function (token, onclick) {
    size = Utils.print_size(token.size)
    icon = FileView.thumbnail(token)
    shortname = Utils.string_limit(50, token.name.fullname)
    class = Label.to_client(token.security) |> LabelView.make_label(_, none)
    <li class="list-group-item item-wlabel" id="{token.file}" onclick={onclick(token.file, _)}>
      <div class="pull-left">{icon}</div>
      <div class="chooser-item-content pull-left" title="{token.name.fullname}" data-placement="bottom" rel="tooltip">
        {shortname}
        <small>{size}</small>
      </div>
      <div class="chooser-item-right">{class}</div>
    </li>
  }
})

type LabelChooser.setup = Chooser.setup(string, Label.id, Label.filter, Label.t, Label.kind)
exposed LabelChooser = Chooser(LabelChooser.setup {
  initRef: "",
  listClass: "",
  emptyFilter: Label.emptyFilter,
  parseFilter: function (value) { {name: value} },
  parseId: Label.idofs,
  fetchItems: function (state, ref, settings) {
    Label.fetch(state.key, ref, AppConfig.pagesize, settings.filter, settings.custom) |>
    Iter.to_list |> Utils.page(_, _.name, "")
  },
  buildItem: function (label, onclick) {
    lb = Label.to_importance(label.category)
    <li class="list-group-item" id="{label.id}" onclick={onclick(label.id, _)}>
      <div class="pull-left">
        <div id="label-{label.id}" class="label_block o-selectable">
          {WB.Label.make(<span class="name">{label.name}</span>, lb)}
        </div>
      </div>
    </li>
  }
})
