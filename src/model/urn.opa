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

type URN.t = {Mode.t mode, Path.t path}

/** Store the current URN for later access. */
private client reference(URN.t) urn_ref = ClientReference.create(URN.init)


// cf. RFC 2141
module URN {

  private function log(msg) { Log.notice("URN:", msg) }

  /** Initial URN. */
  both init = {mode: {dashboard: "all"}, path: []}

  /** Retrieve the currently stored URN (which is normally the current URL). */
  client function URN.t get() { ClientReference.get(urn_ref) }

  /** Change the stored URN. */
  client function void set(URN.t urn) { ClientReference.set(urn_ref, urn) }

  /** Change the stored URN, and modify the history state as well. */
  client function void change(URN.t urn) {
    log(print(urn))
    title = "PEPS " + Mode.title(urn.mode)
    url = print(urn)
    Client.History.pushState(urn, title, url)
    set(urn)
  }

  /** Remove the URN path, only to keep the mode. */
  function trim() {
    urn = get()
    change({urn with path: []})
  }

  function make(Mode.t mode, Path.t path) { ~{mode, path} }

  /** Parser. */
  function parse(string s) {
    pp = function(p) { Path.parse(Text.to_string(p)) }
    urn = parser {
      case "share/" link=Utils.base64_url_string path=(.*):
        make({share: link}, pp(path))

      case "app/" appname=((!"/" .)+) path = (.*) : make({app: Text.to_string(appname), active: ""}, pp(path))
      case "admin/" submode=((!"/" .)+) path = (.*) : make({admin: Text.to_string(submode)}, pp(path))
      case "people/" submode=((!"/" .)+) path = (.*) : make({people: Text.to_string(submode)}, pp(path))

      // TODO: implement password recovery.
      // case "password" : make({admin}, ["password"])

      // TODO: find what this is supposed to do, and implement.
      // case "history" : make({admin}, ["history"])

      case "files:" mode=((!"/" .)+) path=(.*) : make({files: Text.to_string(mode)}, pp(path))
      case "files" path=(.*) : make({files: ""}, pp(path))

      case "settings/" submode=((!"/" .)+) path=(.*) : make({settings: Text.to_string(submode)}, pp(path))

      case "dashboard:" mode=((!"/".)+) path=(.*): make({dashboard: Text.to_string(mode)}, pp(path))
      case "dashboard" path=(.*): make({dashboard: "teams"}, pp(path))
      // case "labels" : make({settings}, ["labels"])
      // case "folders" : make({settings}, ["folders"])

      case box=Box.urn_parser path=(.*): make({messages: box}, pp(path))

      case .* : init
    }
    full = parser { case "/"? ~urn: urn }
    Parser.try_parse(full, s)
  }

  @stringifier(URN.t) function print(URN.t urn) {
    "/{Mode.name(urn.mode)}{Path.print(urn.path)}"
  }

}
