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


package com.mlstate.webmail.controller

import stdlib.core.queue

/**
 * A LdapPool.result is either a ldap or a string which describes the ldap error.
 */
type LdapPool.result = outcome(Ldap.connection, string)

/**
 * Configuration of ldap pool.
 */
type LdapPool.conf = {
  /** Indicates if the pool should output a trace of its action */
  verbose : bool;

  url : string;
  bindCredentials : string;
  bindDN : string;
  domain : string;
  sync_ldap : int;
  sync_mongo : int;
  timeout : int;
  connectTimeout : int;

  /** The maximum number of allocated ldap */
  maxConnections : int;
}

@private type LdapPool.waiter = continuation(LdapPool.result)

@private type LdapPool.state = {
  conf : LdapPool.conf;
  ldap: option(Ldap.connection);
  cnt: int;
  queue: Queue.t(LdapPool.waiter);
}

@private type LdapPool.msg =
    {get : continuation(LdapPool.result)}
  / {release}
  / {reconnect}
  / {getconf : continuation(LdapPool.conf)}
  / {updconf : LdapPool.conf -> LdapPool.conf}
  / {unbind}
  / {stop}

@abstract type LdapPool.t = channel(LdapPool.msg)

@server_private
LdapPool = {{

  @private
  Log = {{

    @private
    @expand
    gen(f, m, fn:string, msg, col) =
      if m.conf.verbose then f("LdapPool({m.conf.url}).{fn}", msg)
      //if m.conf.verbose then Ansi.jlog("LdapPool({m.conf.url}).{fn}: {col}{msg}%d")
      else void

    @expand
    info(m, fn, msg) = gen(@toplevel.Log.info, m, fn, msg, "%c")

    @expand
    debug(m, fn, msg) = gen(@toplevel.Log.debug, m, fn, msg, "%b")

    @expand
    error(m, fn, msg) = gen(@toplevel.Log.error, m, fn, msg, "%r")

  }}

  @private
  ldap_bind(state:LdapPool.state) =
    match LdapController.create_ldap(state.conf.url, state.conf.bindCredentials, state.conf.bindDN, state.conf.domain) with
    | {success=ldap} ->
      {state with ldap={some=ldap}; cnt=0; queue=Queue.empty}
    | {~failure} ->
      do Log.error(state, "ldap_bind", failure)
      {state with ldap={none}; cnt=0; queue=Queue.empty}
    end

  @private
  ldap_unbind(state:LdapPool.state) =
    do match state.ldap with
       | {some=ldap} ->
          do Log.debug(state, "handler", "unbind")
          match @callcc(k -> LdapController.unbind(ldap,"unbind",Continuation.return(k,_))) with
          | {success=_} -> void
          | {~failure} -> Log.error(state, "ldap_unbind", failure)
          end
       | {none} -> void
       end
    {state with ldap={none}; cnt=0; queue=Queue.empty}

  @private @expand monitor(__from, __state) =
     void

  @private return_ldap(state:LdapPool.state, k:LdapPool.waiter) : void =
    Continuation.return(k, 
      match state.ldap with
      | {some=ldap} -> {success=ldap}
      | {none} -> {failure=@i18n("No ldap connection")})

  @private release_ldap(state:LdapPool.state): Session.instruction(LdapPool.state) =
    do monitor("release", state)
    match Queue.rem(state.queue) with
    | ({none}, _) ->
      do Log.debug(state, "handler","ldap back in pool")
      cnt = if state.cnt > 0 then state.cnt - 1 else 0
      {set={state with ~cnt}}
    | ({some=k}, queue) ->
      do Log.debug(state, "handler","reallocate ldap")
      do return_ldap(state, k)
      {set={state with ~queue}}
    end

  @private get_ldap(state:LdapPool.state, k:LdapPool.waiter): Session.instruction(LdapPool.state) =
    do monitor("get", state)
    match state.ldap with
    | {none} ->
      do Log.debug(state, "handler","creating ldap")
      state = ldap_bind(state)
      do return_ldap(state, k)
      {set={state with cnt=1}}
    | {some=_} ->
      if state.cnt < state.conf.maxConnections
      then
        do Log.debug(state, "handler","reuse open ldap")
        do return_ldap(state, k)
        cnt = state.cnt + 1
        {set={state with ~cnt}}
      else
        do Log.debug(state, "handler", "queue caller")
        {set={state with queue=Queue.add(k, state.queue)}}

  @private pool_handler(state:LdapPool.state, msg:LdapPool.msg): Session.instruction(LdapPool.state) =
    match msg with
    | {get=k} -> get_ldap(state, k)
    | {release} -> release_ldap(state)
    | {reconnect} ->
       do monitor("reconnect", state)
       do Log.debug(state, "handler", "reconnect({state.conf.url})")
       state = ldap_unbind(state)
       state = ldap_bind(state)
       {set=state}
    | {getconf=k} ->
       do Continuation.return(k, state.conf)
       {unchanged}
    | {updconf=f} ->
       {set={state with conf=f(state.conf)}}
    | {unbind} ->
       do Log.debug(state, "handler","unbind ldap pool")
       state = ldap_unbind(state)
       {set=state}
    | {stop} ->
       do monitor("stop", state)
       do Log.debug(state, "handler","stop ldap pool")
       _state = ldap_unbind(state)
       {stop}

  @private
  initial_state(conf:LdapPool.conf) =
    ~{conf; cnt=0; ldap={none}; queue=Queue.empty}

  /**
   * Create a pool for ldap.
   * @param conf The initial configuration of the ldap pool
   * @return An ldap pool
   */
  make(conf:LdapPool.conf): LdapPool.t =
    state = initial_state(conf)
    do Log.debug(state, "make","{conf.url}")
    Session.make(state, pool_handler)

  /**
   * Get an ldap from the [pool]. If the maximum of callers are
   * reached wait until an ldap is released (see [LdapPool.conf]).
   * @param pool The ldap pool
   * @return A ldap connected to the ldap server
   */
  get(pool:LdapPool.t) : LdapPool.result =
    @callcc(k -> Session.send(pool, {get=k}))

  /**
   * Same as get but the result is returned to the [callback]
   * @param pool The pool of ldap
   * @param callback The callback which receives the result
   */
  get_async(pool:LdapPool.t, callback) =
    @callcc(k ->
      do Continuation.return(k, void)
      callback(get(pool))
    )

  /**
   * Release [ldap] into the pool. If the ldap not coming from the [pool]
   * then the ldap is just unbind and the pool stay unchanged.
   * @param ldap The ldap to release
   * @param pool The pool of ldap
   */
  release(pool:LdapPool.t) : void =
    Session.send(pool, {release})

  /**
   * Call an unbind and then rebind to the server.
   * @param pool The pool of ldap
   */
  reconnect(pool:LdapPool.t) : void =
    Session.send(pool, {reconnect})

  /**
   * Close all allocated ldap into the ldap [pool]
   * @param pool The pool of ldap
   */
  unbind(pool:LdapPool.t) : void =
    Session.send(pool, {unbind})

  /**
   * Stop the pool of ldap, no more ldap will be allocated.
   * @param pool The pool of ldap
   */
  stop(pool:LdapPool.t) : void =
    Session.send(pool, {stop})


  @private getconf_map(pool, f) = f(getconf(pool))

  /**
   * Returns the configuration of the [pool] of ldap
   * @param pool The pool of ldap
   * @return The configuration of the [pool]
   */
  getconf(pool:LdapPool.t) : LdapPool.conf =
    @callcc(k -> Session.send(pool, {getconf=k}))

  /**
   * Returns the maximum number of allocated ldap of the [pool] of ldap
   * @param pool The pool of ldap
   * @return The maximum number of allocated ldap of the [pool]
   */
  getmax(pool:LdapPool.t) : int =
    getconf_map(pool, _.maxConnections)

  /**
   * Returns the verbosity  of the [pool] of ldap
   * @param pool The pool of ldap
   * @return The verbosity of the [pool]
   */
  getverbose(pool:LdapPool.t) : bool =
    getconf_map(pool, _.verbose)

  @private setconf_map(pool, f) =
    Session.send(pool, {updconf=f})

  /**
   * Set the configuration of the [pool] of ldap
   * @param pool The pool of ldap
   * @param The new configuration of the [pool]
   */
  setconf(pool:LdapPool.t, conf:LdapPool.conf) =
    setconf_map(pool, (_ -> conf))

  /**
   * Set the maximum number of allocated ldap of the [pool] of ldap
   * @param pool The pool of ldap
   * @param maxConnections The new maximum number of allocated ldap of the [pool]
   */
  setmaxConnections(pool:LdapPool.t, maxConnections) =
    setconf_map(pool, (conf -> {conf with ~maxConnections}))

  /**
   * Set the verbosity of the [pool] of ldap
   * @param pool The pool of ldap
   * @param verbose
   */
  setverbose(pool:LdapPool.t, verbose) =
    setconf_map(pool, (conf -> {conf with ~verbose}))

}}

// End of file ldap_pool.opa
