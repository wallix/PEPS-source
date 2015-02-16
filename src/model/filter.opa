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

type comparator = {lt} or {eq} or {gt}

type Filter.expr =
  // Atoms
  { int level, comparator cmp } or
  { string owner } or
  { string name } or
  { Team.key team } or
  { noteam } or            // Label must not have team restrictions.
  { Team.key subteam } or  // Filter sub-teams, key expected.
  { string email } or
  { string desc } or
  // combinators
  { Filter.exprs conj } or
  { Filter.exprs disj } or
  { Filter.expr not } or
  // Parsing errors
  { parse_error }

type Filter.exprs = list(Filter.expr)

type Filter.file = {
  string name,      // Empty == unconstrained.
  Date.date after   // Check edition date.
}


// Filter is a conjunction.
type Filter.t = Filter.exprs

module Filter {

  private quoted = parser {
    case "\"" s=(!"\"" .)* "\"": Text.to_string(Text.ltconcat(s));
    case alpha=Rule.alphanum_string: alpha;
  }

  /* Rules shared amongst all elements. */
  private common = parser {
    case "name" Rule.ws ":" Rule.ws name=quoted: {name: String.lowercase(name)};
    case ("level" | "l") Rule.ws "=" Rule.ws level=Rule.natural: {~level, cmp: {eq}};
    case ("level" | "l") Rule.ws ">" Rule.ws level=Rule.natural: {~level, cmp: {gt}};
    case ("level" | "l") Rule.ws "<" Rule.ws level=Rule.natural: {~level, cmp: {lt}};
    // Others? >/< size? before/after date?
  }

  /* Rules specific to users. */
  user = parser {
  	case e=common: e
    case ("team" | "t") Rule.ws ":" Rule.ws team=quoted:
      team = Team.get_key(String.lowercase(team)) ? ""
      ~{team}
    case "email" Rule.ws ":" Rule.ws email=quoted: {~email};
  }

  /* Rules specific to teams. */
  team = parser {
  	case e=common: e
    case "desc" Rule.ws ":" Rule.ws desc=quoted: {desc: String.lowercase(desc)};
  }

  /* Rules specific to labels. */
  label = parser {
    case e=common: e
    case "team" Rule.ws ":" Rule.ws team=quoted: {team: String.lowercase(team)};
    case "owner" Rule.ws ":" Rule.ws owner=quoted: {owner: String.lowercase(owner)};
  }

  private parse_or = parser {
    case Rule.ws "OR" Rule.ws
  }

  private function element(atom) {
  	parser {
      case n=atom parse_or ns=Rule.parse_list_sep_non_empty(atom, parse_or):
        { disj: (Filter.exprs [n|ns]) }
      case "~" Rule.ws n=atom: {not: Filter.expr n}
      case n=atom: n
      case n=quoted: {name: String.lowercase(n)}
    }
  }

  /**
   * Parse an input filter. Key extractions have to be performed for teams and labels,
   * declared as protected.
   * @param name: the specific rules to use.
   * @param start, page: default start and page values.
   */
  protected function Filter.t parse(atom, string filter) {
  	p = parser {
      case Rule.ws l=Rule.parse_list(element(atom), Rule.ws) Rule.ws: l
    }
    Parser.try_parse(p, filter) ? []
  }

  @expand function compose(Filter.t f0, Filter.t f1) { List.rev_append(f0, f1) }

  /** Application of the filter to different elements. */
  module Apply {
    private function bool generic(Filter.t filter, (Filter.expr, 'a -> bool) fmatch, 'a elt) {
      recursive function generic_aux(Filter.expr e) {
        match (e) {
          case ~{conj}: List.for_all(generic_aux, conj)
          case ~{disj}: List.exists(generic_aux, disj)
          case {not: filter}: not(generic_aux(filter))
          case default: fmatch(e, elt)
        }
      }
      List.for_all(generic_aux, filter)
    }

    protected function bool team(Filter.t filter, Team.t team) {
      function fmatch(filter, team) {
        match (filter) {
          case ~{desc}: String.contains(String.lowercase(team.description),desc)
          case ~{name}: String.contains(String.lowercase(team.name), name)
          case {subteam: d}: Team.is_subteam(team.key, d)
          default: true
        }
      }
      generic(filter, fmatch, team)
    }

    /**
     * The filtering of user readable labels is only partial at this point.
     * The DNF form for teams is not respected and flattened as a disjunction of teams.
     */
    protected function label(Filter.t filter, Label.t label) {
      lteams = Label.get_teams(label)
      function fmatch(filter, label) {
        match ((filter, label.category)) {
          case (~{level, cmp: {lt}}, ~{classified}): classified.level < level
          case (~{level, cmp: {eq}}, ~{classified}): classified.level == level
          case (~{level, cmp: {gt}}, ~{classified}): classified.level > level
          case ({noteam}, ~{classified}): classified.teams == []
          case (~{team}, ~{classified}): if (lteams == []) true else List.mem(team, lteams)
          case (~{name}, _): String.contains(String.lowercase(label.name), name)
          case (~{owner}, {personal}): label.owner == owner
          default: true
        }
      }
      generic(filter, fmatch, label)
    }

    protected function token(Filter.t filter, FileToken.t token) {
      function fmatch(filter, label) {
        match (filter) {
          case ~{name}: String.contains(String.lowercase(token.name.fullname), name)
          default: true
        }
      }
      generic(filter, fmatch, token)
    }

  } // END APPLY

}
