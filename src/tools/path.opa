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



type Path.t = list(string)

module Path {

  @stringifier(Path.t) function to_string(Path.t path) {
    if (path == []) ""
    else List.to_string_using("/", "", "/", path)
  }

  /** Return the full name of a file identified by a path. */
  function fullname(Path.t path, string name) {
    match (path) {
      case []: name
      default: "{path}/{name}"
    }
  }

  function Path.t from_string(path) {
    String.explode("/", path)
    |> List.map(Uri.decode_string, _)
  }

  function Path.t parse(path) { from_string(path) }

  function string print(path) { to_string(path) }

  function normalize(path) {
    List.filter(function(elt) { not(String.is_empty(elt)) }, path)
  }

}
