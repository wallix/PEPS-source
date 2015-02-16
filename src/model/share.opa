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

type Share.link = string
type Share.options = void

/** Share links can apply to either a file or a directory. */
type Share.source =
  { FileToken.id file } or
  { Directory.id dir }

type Share.t = {
  Share.link link,
  Share.options options,
  Share.source src,
  User.key owner,
  Date.date created
}

database Share.t /webmail/share[{link}]
database /webmail/share[_] full

module Share {

  private function log(msg) { Log.notice("Share: ", msg) }
  @expand function switch(src, onfile, ondir) {
    match (src) {
      case ~{file}: onfile(file)
      case ~{dir}: ondir(dir)
    }
  }
  both function isdir(src) { match (src) { case {dir: _}: true ; default: false } }
  both function id(src) { match (src) { case ~{dir}: "{dir}" ; case ~{file}: "{file}" } }

  /**
   * Specification:
   * Share creates link to externally access file tokens or directories.
   * The version receive when using such a link is always the active version.
   */

  function Share.t make(User.key owner, src) { ~{
    link: Random.base64_url(64), options: void,
    src, owner, created: Date.now()
  } }

  private function insert(Share.t share) {
    link = switch(share.src, FileToken.get_link, Directory.get_link)
    match (link) {
      case {some:link}: link
      case {none}:
        /webmail/share[link == share.link] <- share
        switch(share.src,
          FileToken.set_link(_, {some: share.link}),
          Directory.set_link(_, {some: share.link})) |> ignore
        share.link
    }
  }

  function create(User.key key, Share.source src) {
    log("{key} Sharing {src}");
    share = make(key, src)
    insert(share)
  }

  /** Getters. */

  function get(Share.link link) { ?/webmail/share[link == link] }
  function get_name(Share.t share) { switch(share.src, FileToken.get_name, Directory.get_name) }
  function get_all_by(User.key key) { DbSet.iterator(/webmail/share[owner == key]) }
  function get_all() { DbSet.iterator(/webmail/share) }

  /** Properties. */

  /** Return [true] iff the resource can be read by external users. */
  function unprotected(Share.link link) {
    match (get(link)) {
      case {some: share}:
        match (share.src) {
          case {dir: _}: false
          case ~{file}:
            unprotected =
              FileToken.get_security(file) |>
              Option.bind(Label.get, _) |>
              Option.map(Label.allows_internet, _)
            unprotected ? false
        }
      default: false
    }
  }

  /** Return the encryption used by the source. */
  function encryption(Share.source src) {
    match (src) {
      case {dir: _}: {none}
      case ~{file}: FileToken.encryption(file)
    }
  }

  /** Update. */
  function update(Share.t share) {
    /webmail/share[link == share.link] <- share
  }

  /** Remove the link from the database, and reset the link associated with the shared file. */
  function remove(User.key key, Share.t share) {
    log("remove: key={key} link={share.link}")
    Db.remove(@/webmail/share[link == share.link])
    switch(share.src,
      FileToken.set_link(_, {none}),
      Directory.set_link(_, {none}))
  }

  // Convert

  function Share.link string_to_link(string link) {
    link
  }

}
