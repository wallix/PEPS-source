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



type LdapController.search_result('a) =
    {not_found}
 or {'a success}
 or {string failure}

type LdapController.timer = {
  (-> void) start,
  (-> void) stop,
  (int -> void) change
}

module LdapController {

  notice = Log.notice("[LDAP]", _)
  debug = Log.debug("[LDAP]", _)
  error = Log.error("[LDAP]", _)

  pool = Mutable.make(option(LdapPool.t) {none})

  function has_ldap() { Option.is_some(pool.get()) }

  // Stop the pool and empty the pool reference.
  function remove_ldap_pool() {
    match (pool.get()) {
    case {some:p}:
      LdapPool.stop(p)
      pool.set({none});
    case {none}:
      void;
    }
  }

  // Force creation of a new pool, closes down an existing pool, if running.
  function make_ldap_pool(string url, string bindCredentials, string bindDN, string domain, int sync_ldap, int sync_mongo) {
    remove_ldap_pool()
    LdapPool.conf conf =
      ~{ verbose : true,
         url, bindCredentials, bindDN, domain, sync_ldap, sync_mongo,
         timeout : 5000, connectTimeout : 100000, maxConnections : 4 }
    LdapPool.t p = LdapPool.make(conf)
    pool.set({some:p})
  }

  // Check if the pool is open, if not, open it, if so check it has the right configuration.
  function make_ldap_pool_if_changed_or_not_exists(string url, string bindCredentials, string bindDN, string domain,
                                                   int sync_ldap, int sync_mongo) {
    match (pool.get()) {
    case {some:pool}:
      conf = LdapPool.getConf(pool)
      if (url != conf.url || bindCredentials != conf.bindCredentials || bindDN != conf.bindDN || domain != conf.domain
      ||  sync_ldap != conf.sync_ldap || sync_mongo != sync_ldap)
        make_ldap_pool(url, bindCredentials, bindDN, domain, sync_ldap, sync_mongo);
    case {none}:
      make_ldap_pool(url, bindCredentials, bindDN, domain, sync_ldap, sync_mongo);
    }
  }

  function get_ldap_pool() {
    match (pool.get()) {
    case {some:p}:
      match (LdapPool.get(p)) {
      case {success:ldap}:
        {some:ldap};
      case {~failure}:
        error("LdapController.get_ldap_pool: {AppText.failure()} {failure}")
        {none};
      }
    case {none}: {none};
    }
  }

  private function do_ldap_pool(f)() {
    match (pool.get()) {
    case {some:p}: f(p);
    case {none}: void;
    }
  }

  release_ldap_pool = do_ldap_pool(LdapPool.release)
  reconnect_ldap_pool = do_ldap_pool(LdapPool.reconnect)
  unbind_ldap_pool = do_ldap_pool(LdapPool.unbind)

  private function unbind0(Ldap.connection ldap, string name,
                           outcome(void,string) res, (outcome(string,string) -> void) callback) {
    Ldap.unbind(ldap.ldap,
                function (unbind_res) {
                  match ((res,unbind_res)) {
                  case ({success},{success}): callback({success:name});
                  case ({~failure},_): callback({failure:"{name} {AppText.failure()}: {failure}"});
                  case (_,{~failure}): callback({failure:"Ldap.unbind {AppText.failure()}: {failure}"});
                  }
                })
  }

  function unbind(Ldap.connection ldap, string name, (outcome(string,string) -> void) callback) {
    unbind0(ldap, name, {success}, callback)
  }

  private function errCb(Ldap.connection ldap, string name, outcome(void,string) res, (outcome(string,string) -> void) callback) {
    match (res) {
    case {success}: void;
    case {~failure}: error("{name} {AppText.failure()} {failure}");
    }
    unbind0(ldap, name, res, callback)
  }

  private function cbr(callback, res) {
    // We can't leave connections open because ldapjs shuts them down
    // underneath us and doesn't seem able to get back up again the
    // next time we actually need the connection.  For the moment, we
    // are stuck with unbinding the connections once we are done.
    //match (res) {
    //case {failure:_}: reconnect_ldap_pool();
    //default: release_ldap_pool();
    //}
    unbind_ldap_pool()
    release_ldap_pool()
    callback(res)
  }

  function void add(string uid, Ldap.webmailUser wu, callback) {
    match (get_ldap_pool()) {
    case {some:ldap}:
      match (WebmailUser.toJsonString(wu)) {
      case {success:entry}:
        Ldap.add(ldap.ldap, "uid={uid},{ldap.domain}", entry, errCb(ldap,"Ldap.add",_,cbr(callback,_)));
      case {~failure}:
        error("toJsonString {AppText.failure()}: {failure}")
        cbr(callback,{failure:"LdapController.add toJsonString {AppText.failure()}: {failure}"});
      }
    case {none}:
      callback({failure:@i18n("No ldap pool")});
    }
  }

  function void add_user(User.t user, option(binary) password, callback) {
    match (User.to_wuser(user,password)) {
      case {success:wu}: add(user.key, wu, callback);
      case {~failure}: callback({~failure});
    }
  }

  function modify(string uid, Ldap.operation op, RPC.Json.json change, callback) {
    match (get_ldap_pool()) {
    case {some:ldap}:
      change = Ldap.makeChange(op,change)
      Ldap.modify(ldap.ldap, "uid={uid},{ldap.domain}", change, errCb(ldap,"Ldap.modify",_,cbr(callback,_)))
    case {none}:
      callback({failure:@i18n("No ldap pool")});
    }
  }

  function modify_level(string uid, int level, User.status status, list(string) teams, callback) {
    status =
      match (status) {
      case {super_admin}: "super_admin";
      case {admin}: "admin";
      case {lambda}: "lambda";
      }
    modify(uid, {replace}, {Record:[("webmailUserLevel",{Int:level})]},
           function (res) {
             match (res) {
             case {success:_}:
               modify(uid, {replace}, {Record:[("webmailUserStatus",{String:status})]},
                      function (res) {
                        match (res) {
                        case {success:_}:
                          ou = {List:List.map(function (d) { {String:d} },teams)}
                          modify(uid, {replace}, {Record:[("ou",ou)]}, callback);
                        case {failure:_}:
                          callback(res);
                        }
                      })
             case {failure:_}:
               callback(res);
             }
           })
  }

  function modify_block(string uid, bool blocked, callback) {
    modify(uid, {replace}, {Record:[("webmailUserBlocked",{String:if (blocked) "TRUE" else "FALSE"})]}, callback)
  }

  function modify_pass(string uid, string password, callback) {
    modify(uid, {replace}, {Record:[("userPassword",{String:Ldap.SlapPasswd.generate({ssha:4},Binary.of_binary(password))})]},
           callback)
  }

  function modifyDN(string olduid, string newuid, callback) {
    match (get_ldap_pool()) {
    case {some:ldap}:
      Ldap.modifyDN(ldap.ldap, "uid={olduid},{ldap.domain}", "uid={newuid},{ldap.domain}", errCb(ldap,"modifyDN",_,callback))
    case {none}:
      callback({failure:@i18n("No ldap pool")});
    }
  }

  function del(string uid, callback) {
    match (get_ldap_pool()) {
    case {some:ldap}:
      Ldap.del(ldap.ldap, "uid={uid},{ldap.domain}", errCb(ldap,"Ldap.del",_,cbr(callback,_)));
    case {none}:
      callback({failure:"No ldap pool"});
    }
  }

  list(string) user_fields =
    [ "cn", "sn", "uid", "givenName", "userPassword", "mail",
      "webmailUserStatus", "webmailUserLevel", "webmailUserSgn",
      "webmailUserSalt", "webmailUserBlocked", "ou" ]

  list(string) contact_fields =
    [ "sn", "cn", "description", "title", "telephoneNumber", "facsimileTelephoneNumber", "street",
      "postalCode", "physicalDeliveryOfficeName", "ou", "st", "l", "displayName", "givenName", "homePhone",
      "homePostalAddress", "labeledURI", "mail", "mobile", "o", "photo", "uid",
      "webmailContactVisibility", "webmailContactBlocked" ]

  function void search_(Ldap.scope scope, string filter, list(string) attributes, entryfn, finalfn, callback) {
    match (get_ldap_pool()) {
    case {some:ldap}:
      // DO NOT put anything in here which causes the scheduler to switch
      //        it will scramble the order of the events and maybe cause
      //        "end" (ie. status) to arrive before any of the other entries TON OD
      scope = match (scope) { case {base}: "base"; case {one}: "one"; case {sub}: "sub"; }
      Ldap.search(ldap.ldap, ldap.domain,
                  ~{Ldap.default_search_options with scope, filter, attributes },
                  function (Ldap.search_result(string) res) {
                    match (res) {
                    case ~{entry}:
                      match (Json.deserialize(entry)) {
                      case {some:json}:
                        entryfn(json);
                      case {none}:
                        cbr(callback,{failure:@i18n("Bad json {entry}")});
                      }
                    case ~{referral}:
                      cbr(callback,{failure:@i18n("Referral {referral}")});
                    case ~{error}:
                      cbr(callback,{failure:@i18n("Error {error}")});
                    case ~{status}:
                      if (status == 0)
                        cbr(callback,{success:finalfn()})
                      else
                        cbr(callback,{failure:@i18n("Bad status {status}")});
                    }
                  })
    case {none}:
      callback({failure:@i18n("No ldap pool")});
    }
  }

  function void search(Ldap.scope scope, string filter, list(string) attributes, callback) {
    entries = Mutable.make([])
    search_(scope, filter, attributes,
            function (json) { entries.set([json|entries.get()]) },
            function () { entries.get() },
            callback)
  }

  function find(string uid, list(string) fields,
                (RPC.Json.json -> outcome('a,string)) ff,
                (LdapController.search_result('a) -> void) callback) {
    search({sub}, "(&(objectclass=webmailUser)(uid={uid}))", fields,
           function (res) {
             match (res) {
             case {success:[]}: callback({not_found});
             case {success:[json|_]}:
               match (ff(json)) {
               case {success:val}: callback({success:val});
               case {~failure}: callback({~failure});
               };
             case {~failure}: callback({~failure});
             }
           })
  }

  function find_user(string uid, callback) { find(uid, user_fields, User.of_json, callback) }

  function get_user(string uid) {
    @callcc(function (k) {
              find_user(uid,
                        function (res) {
                          match (res) {
                          case {success:(user,pass)}: Continuation.return(k, {some:(user,pass)});
                          default: Continuation.return(k, {none});
                          }
                        })
             })
  }

  function is_valid_password(string uid, string password) {
    if (Option.is_none(pool.get()))
      false
    else {
      @callcc(function (k) {
               find_user(uid,
                         function (res) {
                           match (res) {
                           case {not_found}:
                             notice("LdapController.is_valid_password: uid {uid} not found")
                             Continuation.return(k, false);
                           case {success:(user,pass)}:
                             match (pass) {
                             case {some:pass}:
                               res = Ldap.SlapPasswd.check(Binary.to_binary(pass), password)
                               notice("LdapController.is_valid_password: uid {uid} {if (res) "" else "in"}valid")
                               Continuation.return(k, res);
                             case {none}:
                               notice("LdapController.is_valid_password: uid {uid} no password")
                               Continuation.return(k, false);
                             };
                           case {~failure}:
                             notice("LdapController.is_valid_password: uid {uid} failure {failure}")
                             Continuation.return(k, false);
                           }
                         })
              })
    }
  }

  function find_contact(string uid, callback) { find(uid, contact_fields, Contact.of_json, callback) }

  private function passfail(bool pf, string pre, string msg) {
    if (pf)
      notice(pre^": "^msg)
    else
      error(pre^": "^msg^" failed")
  }

  function validate_ldap_user(User.t luser, option(binary) lpassword) {
    pf = passfail(_, "validate_ldap_user", _)
    match (User.get(luser.key)) {
    case {some:muser}:
      if (not( User.equals(muser, luser) )) {
        pf(User.update(luser.key, function (_) { luser }),"Update user {luser.key}")
      }
      match (User.get_password(luser.key)) {
      case {some: mpassword}:
        match (lpassword) {
        case {some: lpassword}:
          lpassword = Binary.to_string(lpassword)
          if (lpassword != mpassword && lpassword != "")
            pf(User.update_password(luser.key, lpassword),"Update {luser.key} mongo password");
        case {none}:
          notice("validate_ldap_user: remove mongo password")
          // NO, ldap goes funny sometimes and stops sending the userPassword field.
          // This would result in all passwords being deleted.
          //User.unsafe_remove_password(luser.key);
        }
      case {none}:
        match (lpassword) {
        case {some:lpassword}:
          if (Binary.length(lpassword) != 0)
            pf(User.update_password(luser.key, lpassword),"Add {luser.key} mongo password")
        case {none}: void;
        }
      }
    case {none}:
      pf(true,"Adding user {luser.key}")
      lpass = match(lpassword) { case {some: pass}: {hashed: pass}; default: {none} }
      User.insert("ldap", luser, "")
      /*match (lpassword) {
      case {some:lpassword}:
        if (Binary.length(lpassword) != 0)
          pf(User.update_password(luser.key, lpassword),"Add {luser.key} mongo password")
      case {none}: void;
      }*/
    }
  }

  function validate_user(string uid) {
    match (get_user(uid)) {
    case {some:(user, pass)}: validate_ldap_user(user, pass);
    case {none}: void;
    }
  }

  private uids = Mutable.make(stringset StringSet.empty)

  function void synchronize_ldap() {
    search_({sub}, "(&(objectclass=webmailUser)(uid=*))", user_fields,
            function (json) {
              match (User.of_json(json)) {
              case {success:(user,password)}:
                validate_ldap_user(user,password);
              case {~failure}:
                error("LdapController.user_of_json: {AppText.failure()} {failure}");
              }
            },
            function () { void },
            function (res) {
              match (res) {
              case {success}: void;
              case {~failure}: error("LdapController.synchronize_ldap: {AppText.failure()} {failure}");
              }
            })
  }

  //LdapController.timer sync_ldap_timer = Scheduler.make_timer(0,synchronize_ldap)

  function void synchronize_mongo() {
    Iter.iter(function (user) {
                match (get_user(user.key)) {
                case {some:(luser,lpass)}:
                  void;
                case {none}:
                  add_user(user, User.get_password(user.key) |> Option.map(Binary.of_base64, _),
                           function (res) {
                             match (res) {
                             case {success:_}: void;
                             case {~failure}:
                               error("LdapController.synchronize_mongo: {@i18n("add user")} {user.key} {AppText.failure()} {failure}");
                             }
                           })
                }
              }, User.iterator())
  }

  //LdapController.timer sync_mongo_timer = Scheduler.make_timer(0,synchronize_mongo)

  /*function void init_ldap_timers(sync_ldap, sync_mongo) {
    LdapController.sync_ldap_timer.change(sync_ldap)
    if (sync_ldap > 0)
      LdapController.sync_ldap_timer.start()
    else
      LdapController.sync_ldap_timer.stop()
    LdapController.sync_mongo_timer.change(sync_mongo)
    if (sync_mongo > 0)
      LdapController.sync_mongo_timer.start()
    else
      LdapController.sync_mongo_timer.stop()
  }*/


  /** Synchronous functions. */
  module Sync {
    @expand function add(user, password) {
      @callcc(function (cont) { LdapController.add_user(user, password, Continuation.return(cont, _)) })
    }

    @expand function del(uid) {
      @callcc(function (cont) { LdapController.del(uid, Continuation.return(cont, _)) })
    }

    @expand function modify_level(uid, level, status, teams) {
      @callcc(function (cont) { LdapController.modify_level(uid, level, status, teams, Continuation.return(cont, _)) })
    }
  }

  function init() {
    match (UserLdap.get(AppConfig.admin_login)) {
    case {valid:ldap}:
      make_ldap_pool(ldap.url, Binary.to_binary(ldap.password), ldap.binddn, ldap.peopledn, ldap.sync_ldap, ldap.sync_mongo)
      // We can't currently use this because of instability in
      // the LDAP driver.  For now, we just validate an LDAP
      // user value each time a user logs in.
      //init_ldap_timers(ldap.sync_ldap, ldap.sync_mongo)
      void;
    default: void;
    }
  }

}

_x = Scheduler.sleep(10000,LdapController.init)
