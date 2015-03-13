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

/** File entry. */
type Dashboard.file = {
  Journal.Common.event evt,
  string name, int size,
  string mimetype, RawFile.id file,
  bool thumbnail, FileToken.id token
}

/** Aggregation of the events of a time period. */
type Dashboard.summary = {
  stringmap(list(User.key)) adduser,
  stringmap(list(User.key)) deluser,
  stringmap(list(Team.key)) addteam,
  stringmap(list(Team.key)) delteam,
  // Team files. The owners must be the same for all files.
  // Files are flushed as soon as a different entry is received (no accumulation).
  { Date.date start,          // Date of the first file event.
    Journal.Common.event evt, // Type of action.
    int count,                // Number of files.
    list(xhtml) files } files,

  bool suffixDone, // Set to true after the first header change.
  xhtml suffix, // Entires to be inserted in the previous block.
  xhtml block, // Current block.
  xhtml entries // Formatted entry blocks.
}

/** Corresponds to the team view as described by Ida in the issue #192. */
module Dashboard {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[Dashboard]", msg) }
  private function debug(msg) { Log.debug("[Dashboard]", msg) }
  private function warning(msg) { Log.warning("[Dashboard]", msg) }

  /** Round a date to a month. */
  function round_to_month(date) {
    ~{year, month, day:_, h:_, min:_, s:_, ms:_, wday:_} = Date.to_human_readable(date)
    Date.of_human_readable(~{year, month, day: 0, h: 0, min: 0, s: 0, ms: 0, wday: {monday}})
  }

  /** Create the initial limit. */
  function start(ref) {
    today = Date.round_to_day(Date.now())
    yesterday = Date.advance(today, Duration.days(-1))
    log("start: today={today} yesterday={yesterday} ref={ref}")
    if (ref >= today) {span: {today}, date: today}
    else if (ref >= yesterday) {span: {yesterday}, date: yesterday}
    else {span: {month}, date: round_to_month(ref)}
  }

  /** Increment a date limit up to the given date, and return the corresponding separator. */
  function forward(limit, date) {
    id = Dom.fresh_id()
    match (limit.span) {
      case {today}:
        yesterday = Date.advance(limit.date, Duration.days(-1))
        month = round_to_month(limit.date)
        if (date >= yesterday)
          ( {span: {yesterday}, date: yesterday},
            <li class="list-group-item list-group-item-header">Yesterday</li> )
        else if (date >= month)
          ( {span: {month}, date: month},
            <li class="list-group-item list-group-item-header">This month</li> )
        else
          ( {span: {month}, date: round_to_month(date)},
            <li class="list-group-item list-group-item-header">
              <div id={id} onready={Misc.insert_plain_date(id, date, "%B %y")}></div>
            </li> )
      case {yesterday}:
        month = round_to_month(limit.date)
        if (date >= month)
          ( {span: {month}, date: month},
            <li class="list-group-item list-group-item-header">This month</li> )
        else
          ( {span: {month}, date: round_to_month(date)},
            <li class="list-group-item list-group-item-header">
              <div id={id} onready={Misc.insert_plain_date(id, date, "%B %y")}></div>
            </li> )
      case {month}:
        ( {span: {month}, date: round_to_month(date)},
            <li class="list-group-item list-group-item-header">
              <div id={id} onready={Misc.insert_plain_date(id, date, "%B %y")}></div>
            </li> )
    }
  }

  /** Update the contents of a map. */
  private function add(string key, elt, map) {
    StringMap.replace_or_add(key, function (elts) { [elt|elts ? []] }, map)
  }
  private function remove(string key, elt, map) {
    match (StringMap.get(key, map)) {
      case {some: elts}:
        if (List.mem(elt, elts))
          (StringMap.add(key, List.remove(elt, elts), map), true)
        else (map, false)
      default: (map, false)
    }
  }

  private function addall(list(string) keys, elt, map) {
    List.fold(add(_, elt, _), keys, map)
  }
  private function removeall(list(string) keys, elt, mapadd, mapdel) {
    List.fold(function (key, (mapadd, mapdel)) {
      (mapadd, removed) = remove(key, elt, mapadd)
      if (removed) (mapadd, mapdel)
      else (mapadd, add(key, elt, mapdel))
    }, keys, (mapadd, mapdel))
  }

  /**
   * Appends a journal entry to the summary.
   * Entries are treated differently depending on their kind:
   *
   *  - team and user events are cumulated in a map. The modifications
   *   are stored in dedicated maps, and flushed at the end of each period
   *   (today, yesterday, this month, and each month after that).
   *
   *  - consecutive file operations are concatenated. The temporary result is
   *   stored in the {files} field, and is flushed when a different entry is appended
   *   or at the end of each period.
   */
  function append(entry, summary) {
    match (entry.event) {
      // Team creation compensate team deletion.
      case {evt: {new}, ~team}:
        (delteam, addteam) = removeall(entry.owners, team, summary.delteam, summary.addteam)
        ~{summary with addteam, delteam}
      case {evt: {delete}, ~team}:
        {summary with delteam: addall(entry.owners, team, summary.delteam)}
      // User creation compensates user deletion.
      case {evt: {new}, ~user}:
        (deluser, adduser) = removeall(entry.owners, user, summary.deluser, summary.adduser)
        ~{summary with adduser, deluser}
      case {evt: {delete}, ~user}:
        {summary with deluser: addall(entry.owners, user, summary.deluser)}
      case {evt: _, user: _}: summary
      case {evt: _, team: _}: summary
      // File entries.
      case ~{evt, name, size, mimetype, file, thumbnail, token}:
        // Flush previous files if different action.
        summary =
          if (summary.files.evt != evt || summary.files.count > 9)
            {flush_files(summary) with files.evt: evt}
          else summary
        // Append file.
        { summary with
          files: ~{
            count: summary.files.count+1, evt,
            date: if (summary.files.count == 0) entry.date else summary.files.date,
            files: [render_file(name, evt, file, size) | summary.files.files]
          } }
      default:
        summary = flush_files(summary)
        if (summary.suffixDone) {summary with block: summary.block <+> build_entry(entry)}
        else {summary with suffix: summary.suffix <+> build_entry(entry)}
    }
  }

  /** Render a file element. */
  function render_file(name, evt, file, size) {
    if (evt == {delete})
      <a>{name} </a>
      <small>{Utils.print_size(size)}</small>
    else {
      sanid = Uri.encode_string(RawFile.sofid(file))
      sanname = Uri.encode_string(name)
      <a href="/raw/{sanid}/{sanname}" class="dashboard-title">{name} </a>
      <small>{Utils.print_size(size)}</small>
    }
  }

  /** Generic element for compressed entries. */
  // TODO @i18n
  function render_generic(verb, term, class, icon, labelclass, name, key, elts) {
    n = List.length(elts)
    plural = if (n > 1) "s" else ""
    elts = List.filter_map(name, elts)
    key = Team.get_name(key) ? key
    if (n > 0)
      <li class="list-group-item dashboard-entry entry-{class}">
        <i class="fa fa-{icon} pull-left"/>
        <div class="dashboard-content">
          <span class="pull-left dashboard-section">{verb} {term}{plural} ({n})</span>
          <div class="dashboard-inner">
            <span class="label label-{labelclass}">{key}</span>
            <span class="dashboard-title">{String.concat(", ", elts)}</span>
          </div>
        </div>
      </li>
    else
      <></>
  }

  /** Flush the accumulated content of the summary into the entries list. */
  function flush(summary, separator) {
    summary = flush_files(summary)
    rendered =
      StringMap.fold(function (key, elts, list) {
        list <+> render_generic("New", "team", "team", "users", "danger", Team.get_name, key, elts)
      }, summary.addteam, <></>) |>
      StringMap.fold(function (key, elts, list) {
        list <+> render_generic("Deleted", "team", "team", "users", "danger", Team.get_name, key, elts)
      }, summary.delteam, _) |>
      StringMap.fold(function (key, elts, list) {
        list <+> render_generic("New", "user", "user", "users", "warning", User.get_name, key, elts)
      }, summary.adduser, _) |>
      StringMap.fold(function (key, elts, list) {
        list <+> render_generic("Removed", "user", "user", "users", "warning", User.get_name, key, elts)
      }, summary.deluser, _)
    // Return the updated summary.
    if (not(summary.suffixDone))
      { addteam: StringMap.empty, delteam: StringMap.empty,
        adduser: StringMap.empty, deluser: StringMap.empty,
        files: {count: 0, date: Date.now(), files: [], evt: {new}},
        suffixDone: true, suffix: summary.suffix <+> rendered, block: separator, entries: <></> }
    else
      { addteam: StringMap.empty, delteam: StringMap.empty,
        adduser: StringMap.empty, deluser: StringMap.empty,
        files: {count: 0, date: Date.now(), files: [], evt: {new}},
        suffixDone: true, suffix: summary.suffix, block: separator,
        entries:
          summary.entries <+>
          <ul class="list-group">{summary.block <+> rendered}</ul>
      }
  }

  /** Flush only the file content. */
  function flush_files(summary) {
    if (summary.files.count == 0) summary
    else {
      n = summary.files.count
      label = match (summary.files.evt) {
        case {new}: if (n > 1) @i18n("New files ({n})") else @i18n("New file")
        case {delete}: if (n > 1) @i18n("Deleted files ({n})") else @i18n("Deleted file")
        default: if (n > 1) @i18n("Updated files ({n})") else @i18n("Updated file")
      }
      list = List.intersperse(<>, </>, summary.files.files)
      id = Dom.fresh_id()
      filedate = summary.files.date // IMPORTANT: do not replace in function call.
      date = <span id={id} onready={Misc.insert_timer(id, filedate)}></span>
      info = <small class="msg-date pull-right">{date}</small>
      entry =
        <li class="list-group-item dashboard-entry entry-file">
          <i class="fa fa-files pull-left"/>{info}
          <div class="dashboard-content">
            <span class="pull-left dashboard-section">{label}</span>
            <div class="dashboard-inner">{list}</div>
          </div>
        </li>
      if (not(summary.suffixDone))
        { summary with
          files: {count: 0, files: [], evt: {new}, date: summary.files.date},
          suffix: summary.suffix <+> entry }
      else
        { summary with
          files: {count: 0, files: [], evt: {new}, date: summary.files.date},
          block: summary.block <+> entry }
    }
  }

  /** {1} Scrolling. */

  /**
   * Fetch journal entries associated with the given teams, then returned them
   * formatted to a client callback, to be loaded into the view.
   */
  exposed @async function void server_entries(list(User.key) owners, Date.date ref, callback) {
    state = Login.get_state()
    uteams = User.get_teams(state.key)
    teams = List.filter(Team.key_exists, owners)
    if (not(Login.is_logged(state)))
      callback(<></>, <></>, ref, 0)
    else if (not(List.for_all(List.mem(_, uteams), teams)))
      callback(<></>, <></>, ref, 0)
    else {
      t0 = Date.now()
      owners = if (owners == []) uteams else owners
      pagesize = AppConfig.pagesize
      entries = Journal.Main.page(owners, ref, pagesize)


      (suffix, blocks) = build_entries(ref, entries)
      suffix = Xhtml.precompile(suffix)
      blocks = Xhtml.precompile(blocks)
      callback(suffix, blocks, entries.last, entries.size)
    }
  }

  /**
   * Insert the loaded elements into the view.
   * If more entries are to be expected, then restore the {scroll} handler, with updated
   * parameters (set to fetch the following entries).
   */
  client function finish_load(teams, suffix, blocks, ref, size) {
    // Insert suffix in preceding block.
    Dom.select_children(#entries) |> Dom.select_last_one |>
    Dom.put_at_end(_, Dom.of_xhtml(suffix)) |> ignore
    // Insert next blocks.
    #entries =+ blocks
    // Re-bind scroll handler.
    if (size > 0)
      Dom.bind(#entries, {scroll}, scroll(teams, ref, _)) |> ignore
  }

  /**
   * Load more entries, and append them to the end of the list.
   * Called exclusively by the function {scroll}, which detects the optimal moment for loading more entries.
   * This function must NOT be async: we need to deactivate the {scroll} event handler, to avoid duplicate
   * calls to {server_entries}. {server_entries} IS asynchronous, and this ensures the fluidity of the scroll.
   */
  client function void load_more(teams, Date.date ref) {
    debug("load_more: in:{String.concat(",", teams)} ; from:{ref}")
    Dom.unbind_event(#entries, {scroll})                           // Unbind event to avoid multiple requests.
    server_entries(teams, ref, finish_load(teams, _, _, _, _))     // Send request for more elements.
  }

  /**
   * Called on scroll events. Detect when less than a certain amount of entries remain in the list
   * to know when to trigger the function to fetch more entries.
   * Message height is estomated at 80px ofr the purpose of determining the number of entries left in the list.
   * When less than three times the amount of visible entries remain in the list, new entries are fetched.
   * Same as {load_more}, this function needn't be asynchronous.
   */
  client function void scroll(teams, ref, _evt) {
    full = Dom.get_scrollable_size(#entries).y_px
    current = Dom.get_scroll_top(#entries)
    height = Dom.get_height(#entries)
    mvisible = height/80
    mleft = (full-current)/80 - mvisible  // Number of entries left in the list to scroll for.
    if (mleft < 3*mvisible) load_more(teams, ref)
  }

  /** Initialize the list of entries. */
  client function init_entries(teams, _evt) {
    load_more(teams, Date.now())
  }

  /** {1} Construction. */

  function thumbnail(thumbnail, raw) {
    if (thumbnail)
      <div class="file-thumbnail"><img src="/thumbnail/{raw}"/></div>
    else <div class="file-thumbnail"><i class="fa fa-file-o"/></div>
  }

  /**
   * Format a team journal event into a list item.
   * Only messages are concerned, as other entries are added separatly (see append, flush, flush_files).
   */
  protected function build_entry(Journal.Main.t entry) {
    // initiator = (<span class="dashboard-section">{User.get_name(entry.creator)}: </span>)
    info =
      id = Dom.fresh_id()
      if (entry.creator != User.dummy) {
        date = (<span id={id} onready={Misc.insert_timer(id, entry.date)}></span>)
        <small class="msg-date pull-right">{date}</small>
      } else
        <small id={id} onready={Misc.insert_timer(id, entry.date)} class="msg-date pull-right"></small>

    (msg, class, icon) =
      match (entry.event) {
        // Team messages.
        case ~{message, subject, snippet, from}:
          from = match (from) {
            case {internal: ~{email ...}}
            case {external: email}:
              <span class="pull-left dashboard-section" title="{Email.address_to_string(email.address)}" rel="tooltip">
                {Email.to_name(email)}</span>
            case {unspecified: email} -> <span class="dashboard-section">{email}</span>
          }
          ( <>{info}
            <div class="dashboard-content">
              {from}
              <div class="dashboard-inner">
                <span class="dashboard-title">{subject}</span>
                <span class="dashboard-descr">- {snippet} <a href="/inbox/{message}">View more</a></span>
              </div>
            </div></>, "message", "envelope" )
        // Other.
        case ~{evt, dir}:
          ( <>{entry.event}</>, "default", "default" )
        default:
          ( <>Entry cannot be retrieved</>, "error", "error" )
      }

    <li id={entry.id} class="list-group-item dashboard-entry entry-{class}">
      <i class="fa fa-{icon} pull-left"/>{msg}
    </li>
  }

  /**
   * Format a list of journal events.
   * @param ref reference date of the query, needed to detect date changes between two fetches
   *  (and generate the corresponding header).
   */
  protected function build_entries(ref, entries) {
    t0 = Date.now()
    limit = start(ref)
    summary = { // Day summary.
      adduser: StringMap.empty, deluser: StringMap.empty,
      addteam: StringMap.empty, delteam: StringMap.empty,
      files: {count: 0, date: Date.now(), files: [], evt: {new}},
      entries: <></>, block: <></>, suffix: <></>, suffixDone: false
    }
    (summary, _) = List.fold(function (entry, (summary, limit)) {
      if (entry.date < limit.date) {
        (limit, separator) = forward(limit, entry.date)
        summary = flush(summary, separator)
        (append(entry, summary), limit)
      } else (append(entry, summary), limit)
    }, entries.elts, (summary, limit))

    summary = flush(summary, <></>)


    (summary.suffix, summary.entries)
  }

  /** Build the main view. */
  protected function build(Login.state state, string mode, Path.t path) {
    log("build: creating main view")
    owners =
      if (mode == "all") {
        teams = User.get_teams(state.key)
        [state.key|teams]
      } else
        match (Team.get_from_path(path)) {
          case ({some: team}, path): [team|path]
          default: []
        }
    <div id="entries" class="entries">
      <ul class="list-group" onready={init_entries(owners, _)}>
        <li class="list-group-item list-group-item-header">Today</li>
      </ul>
    </div>
  }


  module Sidebar {

    /** Team journal loader. */
    protected function build(state, options, mode) {
      function onclick(mode, teams) { Content.update_callback({mode: {dashboard: mode}, path: teams}, _) }
      teams = User.get_min_teams(state.key)
      // Team elements.
      elts = List.rev_map(function (team) {
        title = (Team.get_name(team) ? team) |> String.capitalize
        path = Team.get_name_path(team)
        ~{title, id: team, icon: "users-o", name: "{team}", onclick: onclick("teams", path)}
      }, teams)
      // Standard elements.
      [ {title: @i18n("Feed"),        id: "all",      icon: "newspaper-o", name: "all",   onclick: onclick("all", [])},
        {separator: AppText.teams(), button: none },
        {title: @i18n("All teams"),   id: "allteams", icon: "users-o",   name: "teams", onclick: onclick("teams", [])} | elts ]
    }

  } // END SIDEBAR

}
