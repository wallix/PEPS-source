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
 * This module provides full-text search functionalities
 * Create an index from a db name
 * Index a document given a set of documents, using tf-idf weight
 * Search documents from a list of words
 */

type indexation =
     {_score: float // tf_idf weight
     ; key: string
     }

type index_element =
     {_id: string
     ; value: list(indexation)
     }

type index = Mongo.collection(index_element)

SearchUtils = {{

  log = ignore //Log.warning("MONGO DB : ", _)

  create_select(r) =
    do log("create select")
    b = Bson.opa2doc(r)
    MongoSelect.create(b)

  create_update(r) =
    do log("create update")
    b = Bson.opa2doc(r)
    MongoUpdate.create(b)

  batch_from_list(v) =
    do log("batch from list")
    MongoCollection.Batch.of_list(v)

  insert(c, v) =
    do log("insert")
    MongoCollection.insert(c, v)

  insert_batch(c, b) =
    do log("insert batch")
    MongoCollection.insert_batch(c, b)

  update(c, s, v) =
    do log("update")
    MongoCollection.update(c, create_select(s), create_update(v))

  push(c, id, v) =
    do log("push")
    update(c, {_id = id}, {`$push` = v})

  delete(c, s) =
    do log("delete")
    MongoCollection.delete(c, create_select(s))

  find_one(c, r) =
    do log("find one")
    MongoCommon.result_to_option(
      MongoCollection.find_one(c, create_select(r))
    )

  find_all(c, r) =
    do log("find all")
    MongoCommon.results_to_list(
      MongoCollection.find_all(c, create_select(r))
    )

  elements(c, set) =
    do log("elements")
    find_all(c, {_id = {`$in` = StringSet.To.list(set)}})
    |> List.fold(
      element, acc -> StringMap.add(element._id, element.value, acc)
    , _, StringMap.empty)

}}

SearchGen = {{

  log = Log.notice("SearchGen", _)
  warning = Log.warning("SearchGen", _)
  debug = Log.debug("SearchGen", _)
  error = Log.error("SearchGen", _)

  /**
   * Return number of occurences of lexem in list
   */
  @private
  count_occurrence(lexem: string, words: list(string)) =
    rec aux(l, acc) = match l with
      | [] -> acc
      | [hd | tl] ->
        if hd == lexem then aux(tl, acc+1)
        else aux(tl, acc)
    aux(words, 0)

  @private
  foi(i: int) = Int.to_float(i)

  @private
  compute_tf_idf(index: index, lexem: string, words: list(string), corpus_size: int, multiple: option(stringmap(list(indexation)))) =
    tf =
      if List.is_empty(words) then 0.00
      else foi(count_occurrence(lexem, words)) / foi(List.length(words))
    idf =
      nb_docs = foi(corpus_size)
      nb_docs_with_lexem =
        match multiple with
        | {some=elements} ->
          match StringMap.get(lexem, elements) with
          | {some=l} -> 1 + List.length(l) |> foi
          | {none} -> 1.00
          end
        | _ ->
          match SearchUtils.find_one(index, {_id = lexem}) with
          | {some=elt: index_element} -> 1 + List.length(elt.value) |> foi
          | {none} -> 1.00
      (nb_docs / nb_docs_with_lexem) |> Math.ln(_)
    tf * idf

  /**
   * Index all words contained in the given document
   * Warning : this can slow down the app if often called
   */
  @server_private
  @async
  index(index: index, document: string, key: string, corpus_size: int) =
    do debug("Index for {key}")
    words = document |> String.explode(" ", _)
    set = StringSet.From.list(words) // a set to avoid indexing more than one time the same word
    _ = Set.iter(
      lexem ->
        tf_idf = compute_tf_idf(index, lexem, words, corpus_size, {none})
        value = {_score =  tf_idf; key = key}
        _ = match SearchUtils.find_one(index, {_id = lexem}) with
        | {some=_: index_element} -> SearchUtils.push(index, lexem, {value = value})
        | {none} -> SearchUtils.insert(index, {_id = lexem; value = [value]})
        void
     , set)
   void

  default_index_context = StringMap.empty
  index_context = UserContext.make(default_index_context) : UserContext.t(stringmap(list(indexation)))

  /**
   * Prepare the User Context to Index all words contained in the given document
   * Prefer this approch if you often call ndexation
   */
  @server_private
  index_multiple(index: index, document: string, key: string, corpus_size: int) =
    do debug("Prepare indexation for {key}")
    words = document |> String.explode(" ", _)
    set = StringSet.From.list(words) // a set to avoid indexing more than one time the same word
    elements = SearchUtils.elements(index, set)
    _ = Set.iter(
      lexem ->
        if (String.length(lexem) <= 512) then
          tf_idf = compute_tf_idf(index, lexem, words, corpus_size, {some=elements})
          value = {_score =  tf_idf; key = key}
          UserContext.change(index ->
            match StringMap.get(lexem, index) with
            | {some = values} -> StringMap.add(lexem, List.cons(value, values), index)
            | _ -> StringMap.add(lexem, [value], index)
            , index_context)
        else
          void
     , set)
   void

  /**
   * Perform the indexation from the User Context
   */
  @server_private
  finalize_index(index) =
    t = Date.now() |> Date.in_milliseconds(_)
    (batch, nb, to_remove) = UserContext.execute(
      map ->
         set = StringMap.fold(
           lexem, values, acc -> StringSet.add(lexem, acc)
         , map, StringSet.empty)
        elements = SearchUtils.elements(index, set)
        size = StringMap.size(map)
        do if size > 0 then error("Perform indexation for {size} words")
        (to_remove, batch) = StringMap.fold(
          lexem, values, (to_remove, acc) ->
            (to_remove, values) = match StringMap.get(lexem, elements) with
              | {some=l} ->
                (List.cons(lexem, to_remove), List.append(l, values))
              | _ -> (to_remove, values)
            element = {_id = lexem; value = values} : index_element
            (to_remove, List.cons(element, acc))
          , map, ([], []))
          (batch, size, to_remove)
        , index_context)
   match batch with
   | [] -> void
   | l ->
     batch = SearchUtils.batch_from_list(l)
     t2 = Date.now() |> Date.in_milliseconds(_)
     _ = SearchUtils.delete(index, {_id = {`$in` = to_remove}})
     _ = SearchUtils.insert_batch(index, batch)
     _ = UserContext.change(_ -> StringMap.empty, index_context)
     t3 = Date.now() |> Date.in_milliseconds(_)
     do error("indexation for {nb} words performed in {t3 - t} ms, with {t3 - t2} ms to write in DB")
     void

   /* SEARCHING */

   /*
   * "toto titi" => chaîne exacte
   * toto titi => au moins l'un des deux mots
   * toto + titi => les deux mots
   */

  @private
  check_lexem(index: index, lexem: string, exact_match: bool) : list(string) =
    search =
      if exact_match then SearchUtils.find_all(index, {_id = lexem})
      else SearchUtils.find_all(index, {_id = {`$regex` = ".*{lexem}.*"}})
    match search with
      | [] -> []
      | l ->
       List.fold(
          elt, acc ->
            List.fold(
              v, acc ->
                if List.mem(v, acc) then acc else List.cons(v, acc)
              , elt.value, acc)
         , l, [])
        |> List.sort_by(indexation -> indexation._score, _)
        |> List.rev_map(indexation -> indexation.key, _)

  @private
  parse_exact(query: string) =
    p = parser
    | "\"" s=Rule.alphanum_string "\"" -> (s, true)
    | s=Rule.alphanum_string -> (s, false)
  Parser.parse(p, query)

  @private
  parse_query(query: string) =
    query = String.replace(" + ", "+", query)
      |> String.replace(" +", "+", _)
      |> String.replace("+ ", "+", _)
    list = String.explode(" ", query)
    List.fold(
      lexems, acc ->
        elt = String.explode("+", lexems) |> List.map(elt -> parse_exact(elt), _)
        List.cons(elt, acc)
    , list, [])

  /**
   * Search all documents containing the query words
   */
  @server_private
  search(index: index, query:string) : list(string) =
    do debug("search for {query}")
    List.fold(
      lexem_list, acc ->
        tmp_res = List.fold(
          (lexem, exact), acc ->
            res = check_lexem(index, lexem, exact)
            match acc with
            | {none} -> {some = res}
            | {some=l} -> {some = List.filter(elt -> List.mem(elt, res), l)}
        , lexem_list, {none})
    |> Option.default([], _)
    List.append(tmp_res, acc)
    , parse_query(query), [])


  /**
   * Return an index as a MongoDb collection
   */
  @server_private
  create_index(db_name: string) =
    mongo = MongoConnection.openfatal("default")
    { db = MongoConnection.namespace(mongo, db_name, "index") }

}}
