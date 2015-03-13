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

LabelView = {{

  /** {1} Utils. **/

  log = Log.notice("[LabelView]", _)
  warning = Log.warning("[LabelView]", _)

  /** {1} Common elements. */

  /**
   * {2} Label selectors.
   *
   * The selector is a clickable label whose action
   * prompts a label chooser for classes. The result of the selection
   * is put the title of the selector.
   */

  /** {3} Class selector. */

  Class = {{

    @private @client voidaction(domid, id, _evt) =
      Log.notice("[Class.voidaction]", "action triggered id={id} domid={domid}")

    /** Select a specific class. */
    @private @client select(id, label, _evt) =
      callback = { onclick= voidaction title= AppText.select() icon= "chevron-down" }
      do Dom.set_attribute_unsafe(#{id}, "title", label.name)
      #{id} <- LabelView.make_label(label, some(callback))

    /** Build the dropdown menu. */
    @private @server_private dropdown(id, labels) =
      list = List.fold(label, list ->
        clabel = Label.full_to_client(label)
        vlabel = LabelView.make_label(clabel, none)
        list <+> <li onclick={select(id, clabel, _)}>{vlabel}</li>
      , labels, <></>)
      <ul id="{id}-dropdown" class="modal-dropdown dropdown-menu">{list}</ul>

    /**
     * Class selector, appearing as a dropdown menu.
     * @param label default classification.
     * @param key active user.
     */
    @server_private selector(id, key, label) =
      clabel = Label.to_client(label)
      callback = { onclick= voidaction title= AppText.select() icon= "chevron-down" }
      // Fetch usable labels.
      usable = Label.Sem.usable_labels(key, {class})
      dropdown = dropdown(id, usable)
      <div class="dropdown">
        <div id={id} data-toggle="dropdown"
            onclick={_evt -> Misc.reposition(id, "{id}-dropdown")}
            class="labels-list dropdown-toggle" title="{clabel.name}">
          {LabelView.make_label(clabel, some(callback))}
        </div>
        {dropdown}
      </div>

  }} // END CLASS

  /**
   * {3} Label selector.
   * The label selector is a list of labels, from which labels can be added
   * (using a chooser) or removed.
   */

  Personal = {{

    /** Remove a label from the list. */
    @private @client remove(domid, _id, _evt) = Dom.remove(#{domid})

    /** Add a single label to the selection. The label must bbe pre-formatted for insertion. */
    @private @client select(id, label, _evt) =
      #{id} +<- LabelView.make_label(label, some({onclick=remove icon="times" title=AppText.remove()}))

    /** Extract the label selection. */
    @client extract(id) =
      Dom.select_inside(#{id}, Dom.select_class("label-label")) |>
      Dom.fold(dom, acc ->
        id = Dom.get_id(dom)
        name = Dom.get_attribute_unsafe(#{id}, "data-name")
        [name|acc]
      , [], _) |>
      List.unique_list_of

    /** Show the label creation modal, or build it if not already created. */
    @private @client create(id, _evt) =
      do if (Dom.is_empty(#{"{id}-modal"})) then
        #main +<- creator(id)
      Modal.show(#{"{id}-modal"})

    /** Save the label created using the creator modal defined below. */
    @private @client save(id, _evt) =
      name = Dom.get_value(#{"{id}-name"}) |> Utils.sanitize
      category =
        if (Dom.is_checked(#{"{id}-personal"})) then {personal: void}
        else {shared: void}
      LabelController.Async.save(none, name, "", category,
        | {success= lid} ->
          do log("Personal.save: creation successful: id={lid} name={name} cat={category}")
          label = Label.full_to_client(~{id=lid name category})
          do select(id, label, 0)
          Dom.hide(#{"{id}-modal"})
        | {failure= msg} ->
          Notifications.error(AppText.Save_failure(), <>{msg}</>)
      )

    /**
     * Minimal view for a personal label creation.
     * FIXME the id should be used to customize field ids.
     * @param id id of the modal window
     * @param callback callback function
     */
    @private @publish
    creator(id: string) =
      body =
      Form.wrapper(
        <div class="form-group">
          <div class="frow">
            <label for="{id}-name" class="fcol control-label">{AppText.name()}:</label>
            <div class="fcol fcol-lg">
              <input type="text" id="{id}-name" class="form-control"/>
            </div>
          </div>
        </div>
        <div class="form-group">
          <div class="frow">
            <label for="{id}-name" class="fcol control-label">{AppText.Category()}:</label>
            <div class="fcol fcol-lg inputs-list ">
              <label class="radio-inline">
                <input type="radio" name="category" id="{id}-personal" value="personal" checked="checked"/>
                <span class="label label-default">{AppText.Personal()}</span>
              </label>
              <label class="radio-inline">
                <input type="radio" name="category" id="{id}-shared" value="shared"/>
                <span class="label label-warning">{AppText.shared()}</span>
              </label>
            </div>
          </div>
        </div>
        , true)
      footer =
        WB.Button.make({
          button=<>{AppText.create()}</>
          callback=save(id, _)
        }, [{primary}])

      Modal.make("{id}-modal",
        <>{AppText.create_label()}</>,
        body, footer, {Modal.default_options with backdrop=false static=false keyboard=false}
      )

    /**
     * Dropdown menu attached to the label selector.
     * The menu contains all user labels, and a link to a label
     * creator.
     */
    @private dropdown(id, labels) =
      // Create new label.
      create =
        <li onclick={create(id, _)} data-toggle="modal" data-target="{id}-modal">
          <a class="btn btn-sm btn-inverse">{AppText.create_label()}</a>
        </li>
      // Usable labels.
      list = List.fold(label, list ->
        label = Label.full_to_client(label)
        clabel = LabelView.make_label(label, none)
        <li onclick={select(id, label, _)}>{clabel}</li> <+> list
      , labels, create)
      // Finish the list.
      <ul id="{id}-dropdown" class="modal-dropdown dropdown-menu">{list}</ul>

    /**
     * Label selector, composed of a label selection and
     * a dropdown menu for selection.
     */
    @server_private selector(id, key, labels) =
      clabels = List.map(LabelView.make_label(_, {some= {onclick= remove icon="times" title=AppText.remove()}}), labels)
      usable = Label.list(key, {shared})
      dropdown = dropdown(id, usable)
      <div class="dropdown">
        <a id="{id}-add" data-toggle="dropdown" class="dropdown-toggle add-label"
            onclick={_evt -> Misc.reposition("{id}-add", "{id}-dropdown")}>
            <i class="fa fa-plus-circle-o"/>
        </a>
        <div id="{id}" class="labels-list">{clabels}</div>
        {dropdown}
      </div>

  }} // END PERSONAL


  /** {1} Options **/

  /**
   * Manage which parts of the label edit/creation form should be revealed, depending
   * on the category selection.
   */
  @client
  radio_onclick(_:Dom.event) =
    if Dom.is_checked(#not_protected) then
      _ = Dom.transition(#{"label_level-form-group"}, Dom.Effect.hide())
      _ = Dom.transition(#label_encryption_group, Dom.Effect.hide())
      _ = Dom.transition(#{"label_teams-form-group"}, Dom.Effect.hide())
      _ = Dom.transition(#allow_internet_group, Dom.Effect.show())
      void
    else if Dom.is_checked(#restricted_diffusion) then
      _ = Dom.transition(#{"label_level-form-group"}, Dom.Effect.show())
      _ = Dom.transition(#label_encryption_group, Dom.Effect.show())
      _ = Dom.transition(#{"label_teams-form-group"}, Dom.Effect.show())
      _ = Dom.transition(#allow_internet_group, Dom.Effect.hide())
      void

  @client
  category_of_string(cat, prev_category) =
    match (cat) with
    | "personal" -> {success={personal}}
    | "shared" -> {success={shared}}
    | "not_protected" -> {success={unprotected=Dom.is_checked(#allow_internet)}}
    | "restricted_diffusion" ->
      level = Int.of_string(Dom.get_value(#label_level))
      encrypt = Dom.is_checked(#label_encryption)
      match (prev_category) with
      | { some= { classified= restriction } } ->
        { success= {classified=~{level; teams=restriction.teams; encrypt}} }
      | _ -> { success={classified=~{level; teams=[]; encrypt}} }
      end
    | _ -> {failure=@i18n("Please choose a label")}

  @server_private label_tabs(admin) =
    <div class="pane-heading">
      <ul class="nav nav-pills">
        <li class="active"><a href="#label-pane" data-toggle="tab">{AppText.Label()}</a></li>
        { if admin then
            <li><a href="#filters-pane" data-toggle="tab">Filters</a></li>
            <li><a href="#users-pane" data-toggle="tab">Users</a></li>
          else
            <li><a href="#messages-pane" data-toggle="tab">{AppText.messages()}</a></li> }
      </ul>
    </div>

  @server_private label_pane_edit(state, label, admin) =
    <div class="tab-pane active" id=#label-pane>
      {editor(state, some(label), admin)}
    </div>

  @server_private label_pane_filters(label) =
    <div class="tab-pane" id=#filters-pane>
      {SuggestView.display_by_label(label)}
    </div>

  @server_private label_pane_users =
    <div class="tab-pane" id=#users-pane>
      <div id=#users_list class="users_list col-md-4 pane-inner-left">
        <div id=#pane_users_content></div>
      </div>
      <div id=#user_viewer class="col-md-8 pane-inner-right"/>
    </div>

  @server_private label_pane_messages =
    <div class="tab-pane" id=#messages-pane>
      <div id=#pane_messages_content>
      </div>
    </div>

  @server_private build_label_panes(state, label:Label.t, admin:bool) =
    label_tabs(admin) <+>
    <div id=#label-panes class="tab-content pane-wrap">
      {label_pane_edit(state, label, admin)}
      { if admin then
          label_pane_filters(label.id) <+>
          label_pane_users
        else label_pane_messages }
    </div>

  @server_private @async
  server_open_callback(state, res) =
    match res with
    | {success= ~{users}} ->
      page = UserController.highlight(users) |> Iter.to_list |> UserController.page
      html = UserView.build_page(state, page, none, User.emptyFilter)
      Dom.transform([#pane_users_content <- html])
    | {success={~messages ~label}} ->
      html = MessageView.Panel.build(state, none, Message.make_page(messages), some("Label: {label}"), none)
      html =
        <div id=#messages_list class="messages_list col-md-4 pane-inner-left">{html}</div>
        <div id=#message_viewer class="message_viewer col-md-8 pane-inner-right"/>
      Dom.transform([#pane_messages_content <- html])
    | {failure=e} -> void
    end

  @publish @async
  server_open(id, admin: bool) =
    state = Login.get_state()
    match Label.get(id) with
    | {some=label} ->
      do #label_viewer <- build_label_panes(state, label, admin)
      LabelController.open(state, label, admin, server_open_callback(state, _))
    // If the label can't be found, call the callback directly.
    | _ -> server_open_callback(state, {failure=AppText.Label_not_found()})
    end

  @client
  do_open(id:Label.id, admin:bool, _) =
    server_open(id, admin)

  /** Refresh the label list only (not the currently displayed label). */
  @publish @async refresh(admin) =
    state = Login.get_state()
    if not(Login.is_logged(state)) then void
    else #content <- build(state, admin)

  /** Open the label editor in creation mode. */
  @publish @async create(admin, _evt: Dom.event) =
    state = Login.get_state()
    if not(Login.is_logged(state)) then
      Notifications.error(@i18n("Label creation"), Content.login_please)
    else
      html = editor(state, none, admin)
      #label_viewer <- html

  /** Delete the selected label. */
  @client delete(id: Label.id, admin, _evt) =
    if Client.confirm(@i18n("Are you sure you want to delete this label?")) then
      LabelController.Async.delete(id,
        // Callback is client-side.
        | {success} ->
          do refresh(admin)
          #label_viewer <- <></>
        | {failure= _message} -> void
      )
    else void

  /** {1} Label creation and edition. **/

  /** Refresh the label list and displayed label on success. */
  @client @async save_callback(admin, res) =
    match (res) with
    | {success=id} ->
      do refresh(admin)
      edit(id, admin)
    | {failure=e} -> Notifications.error(AppText.Save_failure(), <>{e}</>)

  /** Save the changes made to a label definition. */
  @client save(prevlabel, callback, _evt) =
    previd = Option.map(_.id, prevlabel)
    name = Dom.get_value(#label_name) |> Utils.sanitize
    descr = Dom.get_value(#label_description) |> String.trim
    choice = Radio.get_checked([#personal, #shared, #not_protected, #restricted_diffusion], "personal")
    match (category_of_string(choice, Option.map(_.category, prevlabel))) with
    | {success=category} -> LabelController.Async.save(previd, name, descr, category, callback)
    | {failure=e} -> callback({failure=e})
    end

  /** Open the label editor. */
  @publish @async
  edit(id:Label.id, admin) =
    state = Login.get_state()
    match Label.safe_get(state.key, id)
    | {some=label} ->
      html = build_label_panes(state, label, admin)
      #label_viewer <- html
    | _ -> void
    end

  /**
   * Remove a team from the label's classification.
   * @param _id identifier of the dom element whence originated the remove call.
   */
  @client removeTeam(label:Label.t, team:Team.key, admin:bool, _id:string, _evt:Dom.event) =
    match label.category with
    | {classified= restriction} ->
      if List.mem([team], restriction.teams)
        // && Client.confirm(@i18n("Remove team {team.name} from label '{label.name}'?"))
      then
        // If team name is unknown: Team.get_name(d) == {none}, the team gets removed anyway.
        teams = List.filter((d -> d != [team]), restriction.teams)
        category = {classified= {restriction with ~teams}}
        LabelController.Async.save(
          {some= label.id}, label.name, label.description,
          category, save_callback(admin, _))
    | _ -> void
    end

  /** Add a team to a label's classification. */
  @client addTeam(label:Label.t, admin:bool, _evt:Dom.event) =
    (action, excluded) =
      match (label.category) with
      | {classified=restriction} ->
        // Client side callback.
        action(team) =
          if not(List.mem([team], restriction.teams))
          then
            teams = [[team]|restriction.teams]
            category = {classified= {restriction with ~teams}}
            LabelController.Async.save(
              {some= label.id}, label.name, label.description, category,
              save_callback(admin, _))
        // Excluded teams (already chosen).
        (action, List.flatten(restriction.teams))
      | _ ->
        // The action must change the category to a classified label.
        action(team) =
          category = {classified= {
            teams= [[team]]
            level=1 encrypt=false
          }}
          LabelController.Async.save(
            {some= label.id}, label.name, label.description, category,
            save_callback(admin, _))
        // No excluded teams.
        (action, [])
      end
    TeamChooser.create({
      title= @i18n("Add team to {label.name}")
      excluded= excluded user = none action= action
    })

  /** {1} View construction. */

  /**
   * Format a search result. Used exclusively in {Suggest}
   * to format label options.
   */
  display(label: Label.t) = <span class="label">{label.name}</span>

  /** Convert a client label to an xhtml value. */
  @both make_label(label: Label.Client.label, onclick) =
    domid = Random.string(10)
    class = if (label.personal) then ["personal"] else []
    close =
      match (onclick) with
      | {some= ~{onclick icon title}} -> <a onclick={onclick(domid, label.id, _)} class="fa fa-{icon}" title={title}></a>
      | _ -> <></>
      end
    <span id="{domid}" data-name="{label.name}" class="label-label">{
      WB.Label.make(
        <span id="{domid}-name" title="{label.name}" class={class}>{label.name}{close}</span>,
        label.importance
      )
    }</span>

  @server_private
  build_labels(labels: list(Label.t), with_admin:bool) =
    List.map(label ->
      id = label.id
      lb = Label.to_importance(label.category)
      level = Label.get_level(label)
      lvl = if level > 0 then AppConfig.level_view(level) else ""
      content =
        <div class="pull-right"><span class="badge">{lvl}</span></div> <+>
        WB.Label.make(<span class="name">{label.name}</span>, lb)
      // Return list item with onlick handler.
      (content, do_open(id, with_admin, _))
    , labels) |>
    ListGroup.make(_, AppText.no_labels())

  /** Fetch and layout the teams listed as part of a classified label. */
  @server_private layoutTeams(label, admin) =
    remove(team) = {some= removeTeam(label, team.key, admin, _, _)}
    teams =
      match (label.category) with
      | {classified= restriction} ->
        List.filter_map(d ->
          match (d) with
          | [d] -> Team.get(d)
          | _ -> none
          end, restriction.teams)
      | _ -> []
      end
    TeamView.layout(teams, remove, [])

  /** Build the label viewer / editor. */
  @server_private editor(state: Login.state, label: option(Label.t), with_admin) =
    is_admin = with_admin && Login.is_admin(state)
    ( name, description, level, pre_label_teams, personal, shared,
      not_protected, classified, internal, internet, encrypt ) =
      match label with
      | {some= label} -> (
          label.name, label.description, "{Label.get_level(label)}",
          String.concat(",", Label.get_teams(label)),
          Label.is_personal(label), Label.is_shared(label),
          Label.is_unprotected(label), Label.is_classified(label), Label.is_internal(label),
          Label.allows_internet(label), Label.encrypt(label.category)
        )
      | {none} -> ("", "", "1", "", true, false, true, false, false, true, false)
      end
    dosave = save(label, save_callback(with_admin, _), _) // Save action.
    name =
      Form.line({Form.Default.line with
        label= AppText.name(); id= "label_name";
        value= name; action= some(dosave)
      })
    description =
      Form.line({Form.Default.line with
        label= AppText.description(); id= "label_description";
        value= description; action= some(dosave)
      })
    level =
      if not(is_admin) then <></>
      else
        Form.line({Form.Default.line with
          label= @i18n("Minimum level"); id= "label_level";
          typ= "number"; value= level;
          display= classified;
        })
    encryption = if (is_admin) then Checkbox.make("label_encryption", AppText.encryption(), encrypt, classified) else <></>
    internet = if (is_admin) then Checkbox.make("allow_internet", AppText.allow_internet(), internet, not_protected) else <></>
    // Not displayed at label creation, even for classified labels.
    // TODO: implement team selector for this case.
    teams =
      match (label) with
      | {some= label} ->
        style = if (classified) then "" else "display:none;"
        <div id="label_teams-form-group" class="form-group" style="{style}">
          <label class="control-label">{AppText.teams()}
            <a onclick={addTeam(label, with_admin, _)} class="fa fa-plus-circle-o"/>
          </label>
          <div id="label_teams">{layoutTeams(label, with_admin)}</div>
        </div>
      | {none} -> <></>
      end
    save_text = if Option.is_some(label) then AppText.save() else AppText.create()
    save_button =
      match Option.map(_.category, label) with
      | {some={internal}} -> <></>
      | _ ->  WB.Button.make({
              button=<>{@i18n("Save changes")}</>
              callback=dosave}, [{primary}])
      end
    delete =
      if internal then <></>
      else
        match label with
        | {some= label} ->
          <div class="pull-right">
            <a class="btn btn-sm btn-default" onclick={delete(label.id, with_admin, _)}>
              <i class="fa fa-trash-o"/> {AppText.delete()}
            </a>
          </div>
        | {none} -> <></>
        end
    title =
      match label with
      | {none} -> AppText.create_label()
      | {some=label} -> AppText.edit_label(label.name)
      end
    kind =
      if internal then <span class="label label-warning">{AppText.Internal()}</span>
      else
        Radio.list(
          if is_admin then [
            { id= "not_protected" value= "not_protected"
              text= <span class="label label-success">{AppText.Not_Protected()}</span>
              checked= not_protected onclick= some(radio_onclick) },
            { id= "restricted_diffusion" value= "restricted_diffusion"
              text= <span class="label label-danger">{@i18n("Restricted Diffusion")}</span>
              checked= classified onclick= some(radio_onclick) }
          ] else [
            { id= "personal" value= "personal"
              text= <span class="label label-default">{AppText.Personal()}</span>
              checked= personal onclick= none },
            { id= "shared" value= "shared"
              text= <span class= "label label-warning">{AppText.shared()}</span>
              checked= shared onclick= none }
          ]
        )
    Form.wrapper(
      <div class="pane-heading">
        {delete}
        <h3>{title}</h3>
      </div> <+>
      name <+> description <+>
      level <+> encryption <+> teams <+>
      Form.label(AppText.Category(), "", kind) <+>
      internet <+> <div class="form-group">{save_button}</div>
    , false)

  @server_private
  build(state:Login.state, admin:bool) =
    status = if admin then {super} else {logged}
    Content.ensure(status, state,
      title = if (admin) then AppText.classification() else AppText.labels()
      kind = if (admin) then {class} else {shared}
      labels = Label.list(state.key, kind)
      <div id=#labels_list class="pane-left">
        <div class="pane-heading">
          <h3>{title}</h3>
        </div>
        { build_labels(labels, admin) }
      </div>
      <div id=#label_viewer class="pane-right"></div>
    )

}}
