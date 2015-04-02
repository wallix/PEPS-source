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

module ShareView {

  private function log(msg) { Log.notice("ShareView: ", msg) }

  /**
   * Build link icons.
   * @param linkable an object with at least two fields: an optional link and an owner.
   */
  @expand protected function xhtml make_link(linkable, option(Share.t) share) {
    match (linkable.link) {
      case {some: link}:
        match (share) {
          case {none}: <span><a href="/share/{link}" target="_blank" class="fa fa-link"></a></span>
          case {some: share}:
            if (share.owner == linkable.owner) <span><a href="/share/{link}" target="_blank" class="fa fa-link"></a></span>
            else <></>
        }
      default: <></>
    }
  }

  client function select_link(Share.link link, _) {
    Dom.remove_class(dollar("#files_list .active"), "active");
    activate = Dom.select_parent_one(Dom.select_parent_one(#{"link-{link}"}))
    Dom.add_class(activate, "active");
  }

  client function open_link(Share.link link, _) {
    _ = Client.winopen("/share/{link}", {_blank}, [], true)
    void
  }

  private function WBootstrap.Table.line build_line(Share.t share, name, path, icon) {
    link = share.link
    date = share.created
    link_id = "link-{share.link}"
    link_create_id = "link-{share.link}-create"
    milli_date = "{Date.in_milliseconds(date)}"
    { elts: [
        { xhtml:
            <div id="{link_id}" class="file-thumbnail o-selectable">
              {icon}
              <a title="{path}" href="/share/{link}" target="_blank"
                  class="link o-selectable">{name}</a>
            </div> },
        { xhtml:
            <span id="{link_create_id}" class="link_created o-selectable"
                  onready={Misc.insert_timer(link_create_id, date)}></span>,
          decorator: Utils.data_value(milli_date, _) },
        { xhtml:
            <span class="link_remove">
                <a title="{@intl("Remove {path}")}"
                    onclick={FileView.Common.unshare(link)}><span class="fa fa-trash-o"/> {AppText.remove()}</a>
            </span> } ],
      handles: [
        {name:{click}, value:{expr:@public_env(select_link(link, _))}},
        {name:{dblclick}, value:{expr:@public_env(open_link(link, _))}} ]
    }
  }

  private function WBootstrap.Table.line build_directory_line(Share.t share, Directory.id dir) {
    match (Directory.get(dir)) {
      case {none}: WBootstrap.Table.line :> []
      case {some: dir}:
        name = dir.name
        path = Directory.get_path(dir.id, true)
        icon = <span class="fa fa-lg fa-folder-o"/>
        build_line(share, name, path, icon)
    }
  }

  private function WBootstrap.Table.line build_file_line(Share.t share, FileToken.id tid) {
    match (FileToken.get(tid)) {
      case {none}: WBootstrap.Table.line :> []
      case {some: token}:
        name = token.name.fullname
        path = Option.map(Directory.get_path(_, true), token.dir) ? []
        mimetype = RawFile.get_mimetype(token.active) ? "text/plain"
        icon = <span class="fa fa-2x {FileView.mimetype_to_icon(mimetype)}"/>
        build_line(share, name, path, icon)
    }
  }

  private function WBootstrap.Table.line build_share_line(state, Share.t share) {
    link = share.link
    date = share.created
    Share.switch(share.src, build_file_line(share, _), build_directory_line(share, _))
  }

  protected function build(Login.state state) {
    log("{state.key} Building shared links")
    all_links = Share.get_all_by(state.key)
    table_content = Iter.map(build_share_line(state, _), all_links) |> Iter.to_list
    if (List.is_empty(table_content))
      <div class="pane-content"><p class="empty-text">{AppText.no_links()}</p></div>
    else
      <div id="files_list" class="pane-content"
          onready={function(_) { TableSorter.init(Dom.select_class("tablesorter")) }}>
          { WB.Table.hover(
            [ { xhtml: <>{AppText.name()}</>, decorator: identity },
              { xhtml: <>{AppText.created()}</>, decorator: function(x) {
                Utils.data_sort_initial("descending", x)
                |> Utils.data_type("numeric", _)
              } },
              { xhtml:<>{AppText.actions()}</>, decorator: Utils.data_sort_ignore(_) }
            ], table_content)
          |> Xhtml.update_class("table-responsive table-hover tablesorter tablesorter-bootstrap", _)
        }
      </div>
  }

}
