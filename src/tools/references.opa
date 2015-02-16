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



/**
 * Signature of the referencing module. It encapsulates a ClientReference
 * of a stringmap, and provides operations to set and get values referenced
 * by keys in this map.
 * @param 'elt the type of the values being referenced.
 */
type refset('elt) = {
  (string -> option('elt))                       get,
  (string, 'elt -> void)                         set,
  (string, ('elt -> 'elt) -> void)               update,
  (string -> void)                               remove,
  (string -> bool)                               mem,

  (-> stringmap('elt))                           getall,
  (stringmap('elt) -> void)                      setall,
  ((stringmap('elt) -> stringmap('elt)) -> void) updateall,
  (-> void)                                      clear,

  (-> bool)                                      is_empty,
  (-> list('elt))                                list
}

/**
 * Generic implementation of the signature [refset].
 * RefSet is dependent upon the type of elements referenced,
 * and a new instance needs to be created for each different use.
 */
client (reference(stringmap) -> refset) module RefSet(reference(stringmap) ref) {

  function get(id)            { StringMap.get(id, ClientReference.get(ref)) }
  function set(id, elt)       { ClientReference.update(ref, function(map) { StringMap.add(id, elt, map) }) }
  function remove(id)         { ClientReference.update(ref, function(map) { StringMap.remove(id, map) }) }
  function mem(id)            { ClientReference.get(ref) |> StringMap.mem(id, _) }
  function update(id, change) {
    ClientReference.update(
      ref,
      function(map) {
        match (StringMap.get(id, map)) {
          case {some: elt}: StringMap.add(id, change(elt), map)
          default: map
        }
      })
  }

  function clear()            { ClientReference.set(ref, StringMap.empty) }
  function getall()           { ClientReference.get(ref) }
  function setall(map)        { ClientReference.set(ref, map) }
  function updateall(change)  { ClientReference.update(ref, change) }

  function is_empty()         { ClientReference.get(ref) |> StringMap.is_empty }
  function list()             { ClientReference.get(ref) |> StringMap.To.val_list }
}
