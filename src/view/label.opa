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
                <span class="label label-info-inverse">{AppText.Personal()}</span>
              </label>
              <label class="radio-inline">
                <input type="radio" name="category" id="{id}-shared" value="shared"/>
                <span class="label label-warning-inverse">{AppText.shared()}</span>
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

  /** Open **/

  label_tabs(with_admin) =
    <div class="pane-heading">
      <ul class="nav nav-pills">
        <li class="active"><a href="#label-pane" data-toggle="tab">{AppText.Label()}</a></li>
        { if with_admin then
            <li><a href="#filters-pane" data-toggle="tab">Filters</a></li>
            <li><a href="#users-pane" data-toggle="tab">Users</a></li>
          else
            <li><a href="#messages-pane" data-toggle="tab">{AppText.messages()}</a></li>
        }
      </ul>
    </div>

  label_pane_edit(state, label, with_admin) =
    <div class="tab-pane active" id=#label-pane>
      {build_form_tab(state, some(label), with_admin)}
    </div>

   //<a class="pull-right" onclick={do_delete(id, with_admin, _)}><i class="fa fa-trash-o"/> {AppText.delete()}</a>

  label_pane_filters(state, label_opt) =
    <div class="tab-pane" id=#filters-pane>
      {match label_opt
        | {none} -> <>Create the label first</>
        | {some=label} -> SuggestView.display_by_label(label.id)
      }
    </div>

  label_pane_users(state) =
    <div class="tab-pane" id=#users-pane>
      <div id=#users_list class="users_list col-md-4 pane-inner-left">
        <div id=#pane_users_content></div>
      </div>
      <div id=#user_viewer class="col-md-8 pane-inner-right"/>
    </div>

  label_pane_messages(state) =
    <div class="tab-pane" id=#messages-pane>
      <div id=#pane_messages_content>
      </div>
    </div>

  build_label_panes(state, label:Label.t, with_admin) =
    <>
    {label_tabs(with_admin)}
    <div id=#label-panes class="tab-content pane-wrap">
      {label_pane_edit(state, label, with_admin)}
      { if with_admin then
          label_pane_filters(state, some(label)) <+>
          label_pane_users(state)
        else
          label_pane_messages(state) }
    </div>
    </>

  @server_private @async
  server_open_callback(state, res) =
    match res
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

  @publish @async
  server_open(id, admin: bool) =
    state = Login.get_state()
    match Label.get(id) with
    | {some=label} ->
      do #label_viewer <- build_label_panes(state, label, admin)
      LabelController.open(state, label, admin, server_open_callback(state, _))
    // If the label can't be found, call the callback directly.
    | _ -> server_open_callback(state, {failure=AppText.Label_not_found()})

  @client
  do_open(id:Label.id, admin: bool, _) =
    server_open(id, admin)


  /** {1} Label page refresh. */

  @publish @async
  refresh(admin) =
    state = Login.get_state()
    if not(Login.is_logged(state)) then void
    else #content <- build(state, admin)

  /** {1} Open the label creation form. */

  @client @async
  create_callback =
  | {success=html} -> #label_viewer <- html
  | {failure=e} ->
    Notifications.error(@i18n("Label creation"), <>{e}</>)

  @publish @async
  create(admin, _evt: Dom.event) =
    state = Login.get_state()
    if not(Login.is_logged(state)) then
      create_callback({failure= Content.login_please})
    else
      html = build_form_tab(state, none, admin)
      create_callback({success= html})

  /** {1} Label deletion. **/

  @client
  delete(id: Label.id, admin, _evt) =
    if Client.confirm(@i18n("Are you sure you want to delete this label?")) then
      LabelController.Async.delete(id,
        // Callback is client-side.
        | {success} ->
          do refresh(admin)
          #label_viewer <- <></>
        | {failure=e} -> void
      )
    else void

  /** {1} Label creation and edition. **/

  @client @async
  save_callback(admin, res) =
    match (res) with
    | {success=id} ->
      do refresh(admin)
      edit(id, admin)
    | {failure=e} -> Notifications.error(AppText.Save_failure(), <>{e}</>)

  @client
  save(prevlabel, callback, _evt) =
    previd = Option.map(_.id, prevlabel)
    name = Dom.get_value(#label_name) |> Utils.sanitize
    descr = Dom.get_value(#label_description) |> String.trim
    choice = Radio.get_checked([#personal, #shared, #not_protected, #restricted_diffusion], "personal")
    match (category_of_string(choice, Option.map(_.category, prevlabel))) with
      | {success=category} -> LabelController.Async.save(previd, name, descr, category, callback)
      | {failure=e} -> callback({failure=e})
    end

  @publish @async
  edit(id:Label.id, admin) =
    state = Login.get_state()
    match Label.safe_get(state.key, id)
    | {some=label} ->
      html = build_label_panes(state, label, admin)
      edit_callback({success=html})
    | _ -> void // edit_callback({failure=AppText.Label_not_found()})
    end

  @client @async
  edit_callback =
  | {success=html} -> #label_viewer <- html
  | {failure=e} -> void

   @client
  do_edit(id:Label.id, with_admin, _) = edit(id, with_admin)

  /** Display **/

  display(label : Label.t) =
    <span class="label">{label.name}</span>

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
  build_labels(labels:list(Label.t), with_admin:bool) =
    labels_list =
      List.map(label ->
        id = label.id
        lb = Label.to_importance(label.category)
        level = Label.get_level(label)
        lvl = if level > 0 then AppConfig.level_view(level) else ""
        content = <div class="pull-right">
          <span class="badge">{lvl}</span>
        </div> <+>
        WB.Label.make(
          <span class="name" onclick={do_open(id, with_admin, _)}>{label.name}</span>
        , lb)
        (content, (e -> Log.info("action", "item: {id}")))
      , labels)
    ListGroup.make_action(labels_list, AppText.no_labels())

  /** Build **/

  @both
  select_if(xhtml:xhtml, sel:bool) =
    if sel then Xhtml.add_attribute_unsafe("selected", "selected", xhtml)
    else xhtml

  @client
  form_ready(e:Dom.event) =
    do radio_onclick(e)
    void

  @server_private
  label_id =
  | {some=label} -> some(label.id)
  | {none} -> none

  // form in tab
  build_form_tab(state:Login.state, prev_label_opt:option(Label.t), with_admin) =
    <>
      {build_label_view(state, prev_label_opt, with_admin)}
    </>

  @client add_team_callback(label, with_admin, team) =
  // match DeptRef.get("choose_team_modal") with
  // | {none} -> void
  // | {some=team} ->
    match label.category with
    | {classified=restriction} ->
      if not(List.mem([team], restriction.teams))
        // && Client.confirm(@i18n("Add team '{team.name}' to label {label.name}?"))
      then
        teams = [[team]|restriction.teams]
        cat = {classified= {restriction with ~teams}}
        LabelController.Async.save(
          {some=label.id}, label.name, label.description, cat,
          save_callback(with_admin, _))
    | _ -> void
    end

  @client client_remove_team(label:Label.t, team:Team.t, with_admin:bool, id:string, ev:Dom.event) =
    match label.category with
    | {classified= restriction} ->
      if List.mem([team.key], restriction.teams)
        // && Client.confirm(@i18n("Remove team {team.name} from label '{label.name}'?"))
      then
        // If team name is unknown: Team.get_name(d) == {none}, the team gets removed anyway.
        teams = List.filter((d -> d != [team.key]), restriction.teams)
        cat = {classified= {restriction with ~teams}}
        do LabelController.Async.save(
          {some=label.id}, label.name, label.description, cat,
          save_callback(with_admin, _))
        do #{"label_teams"} <- client_get_label_teams(label, with_admin)
        void
      else void
    | _ -> void
    end

  @client do_add_team(key, label, with_admin, ev:Dom.event) =
    TeamChooser.create({
      title= @i18n("Add team to {label.name}")
      excluded= Label.get_teams(label)
      user = none
      action= add_team_callback(label, with_admin, _)
    })

  @publish
  get_label_teams(label, with_admin) =
    state = Login.get_state()
    remove_click(team) = {some=client_remove_team(label, team, with_admin, _, _)}

    teams =
      match (label.category) with
      | {classified=restriction} ->
        List.filter_map(d ->
          match (d) with
          | [d] -> Team.get(d)
          | _ -> {none}
          end, restriction.teams)
      | _ -> []
      end
    TeamView.layout_teams(teams, remove_click, [])

  @client client_get_label_teams(label, with_admin) = get_label_teams(label, with_admin)


  @server_private
  build_label_view(state:Login.state, prev_label_opt:option(Label.t), with_admin) =
    is_admin = with_admin && Login.is_admin(state)
    (pre_label_name, pre_label_descr, pre_label_level, pre_label_teams,
     personal, shared, not_protected, restricted_diffusion, internal,
     allow_internet, encrypt) =
      match prev_label_opt
      {some=label} -> (label.name, label.description, "{Label.get_level(label)}", String.concat(",", Label.get_teams(label)),
                       Label.is_personal(label), Label.is_shared(label),
                       Label.is_unprotected(label), Label.is_classified(label), Label.is_internal(label),
                       Label.allows_internet(label), Label.encrypt(label.category))
      {none} -> ("", "", "1", "", true, false, true, false, false, true, false)
    add_btn =
      match prev_label_opt
      {some=label} -> <a onclick={do_add_team(state.key, label, with_admin, _)} class="fa fa-plus-circle-o"/>
      {none} -> <></>
    name_line =
      Form.line({Form.Default.line with
        label= AppText.name(); id= "label_name";
        value= pre_label_name;
        action= some(save(prev_label_opt, save_callback(with_admin, _), _))
      })
    descr_line =
      Form.line({Form.Default.line with
        label= AppText.description(); id= "label_description";
        value= pre_label_descr;
        action= some(save(prev_label_opt, save_callback(with_admin, _), _))
      })
    level_line =
      if not(is_admin) then <></>
      else
        Form.line({Form.Default.line with
          label=@i18n("Minimum level"); id="label_level";
          typ="number"; value=pre_label_level;
          display=restricted_diffusion;
        })
    encryption =
      if (is_admin) then Checkbox.make("label_encryption", AppText.encryption(), encrypt)
      else <></>
    internet =
      if (is_admin) then Checkbox.make("allow_internet", AppText.allow_internet(), allow_internet)
      else <></>
    teams_inner =
      <>
        <label class="control-label">{AppText.teams()} {add_btn}</label>
        <div id="label_teams">{Option.map(label -> get_label_teams(label, with_admin), prev_label_opt) ? <></>}</div>
      </>
    teams_line =
      if restricted_diffusion && Option.is_some(prev_label_opt) then
        <div id="label_teams-form-group" class="form-group">{teams_inner}</div>
      else
        <div id="label_teams-form-group" class="form-group" style="display:none">{teams_inner}</div>
    save_text = if Option.is_some(prev_label_opt) then AppText.save()
                else AppText.create()
    save_button =
      match Option.map(_.category, prev_label_opt) with
      | {some={internal}} -> <></>
      | _ ->  WB.Button.make({
              button=<>{@i18n("Save changes")}</>
              callback=save(prev_label_opt, save_callback(with_admin, _), _)}, [{primary}])
    delete_button =
      if internal then <></>
      else
        match prev_label_opt
        {some=label} ->
          <div class="pull-right">
            <a class="btn btn-sm btn-default" onclick={delete(label.id, with_admin, _)}>
              <i class="fa fa-trash-o"/> {AppText.delete()}
            </a>
          </div>
        {none} -> <></>
    title =
      match prev_label_opt with
      | {none} -> AppText.create_label()
      | {some=label} -> AppText.edit_label(label.name)

    Form.wrapper(
      <div class="pane-heading">
        {delete_button}
        <h3>{title}</h3>
      </div> <+>
      name_line <+> descr_line <+>
      level_line <+> encryption <+>
      teams_line <+>

      Form.label(
        AppText.Category(), "",
        (if internal then
          <span class="label label-warning-inverse">{AppText.Internal()}</span>
         else
          Radio.list(
          if is_admin then
            [{id="not_protected" value="not_protected" checked=not_protected
              text=<span class="label label-success-inverse">{AppText.Not_Protected()}</span> onclick=some(radio_onclick)},
              {id="restricted_diffusion" value="restricted_diffusion"
               checked=restricted_diffusion
               text=<span class="label label-danger-inverse">{@i18n("Restricted Diffusion")}</span>
               onclick=some(radio_onclick)}]
          else
            [{id="personal" value="personal" checked=personal
           text=<span class="label label-info-inverse">{AppText.Personal()}</span> onclick=some(radio_onclick)},
           {id="shared" value="shared" checked=shared
            text=<span class="label label-warning-inverse">{AppText.shared()}</span>
            onclick=some(radio_onclick)}]
        ))
      ) <+> internet <+>
      <div class="form-group">{save_button}</div>
    , false)
    |> Xhtml.add_onready(form_ready, _)

  @server_private
  build(state:Login.state, admin:bool) =
    status =
      if admin then {super}
      else {logged}
    Content.ensure(status, state,
      kind = if (admin) then {class} else {shared}
      labels = Label.list(state.key, kind)

      <div id=#labels_list class="pane-left">
        <div class="pane-heading">
          <h3>{if admin then AppText.classification() else AppText.labels()}</h3>
        </div>
        { build_labels(labels, admin) }
      </div>
      <div id=#label_viewer class="pane-right">
      </>
    )

}}
