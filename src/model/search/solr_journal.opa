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

type SolrJournal.journal_entry_type = {add} or {remove} or {null}

type SolrJournal.solr_mail = {
  string id,
  string from,
  list(string) to,
  list(string) cc,
  list(string) bcc,
  string subject,
  string content,
  string date,
  list(string) in,
  string owner,
  SolrJournal.journal_entry_type entry_type,
  Date.date journal_date
}

type SolrJournal.solr_file = {
  string id,           // RawFile id.
  string name,
  string mimetype,
  SolrJournal.journal_entry_type entry_type,
  Date.date journal_date
}

type SolrJournal.solr_user = {
  string id,
  string first_name,
  string last_name,
  string email,
  string status,
  int level,
  list(string) teams,
  string sgn,
  SolrJournal.journal_entry_type entry_type,
  Date.date journal_date
}

type SolrJournal.solr_contact = {
  list(string) emails,
  string id,
  string owner,
  string displayName,
  // string name,
  string nickname,
  string blocked,
  SolrJournal.journal_entry_type entry_type,
  Date.date journal_date
}

database SolrJournal.solr_mail /webmail/solr_mail_journal[{id, owner}]
database /webmail/solr_mail_journal[_]/entry_type = {null}

database SolrJournal.solr_file /webmail/solr_file_journal[{id}]
database /webmail/solr_file_journal[_]/entry_type = {null}

database SolrJournal.solr_user /webmail/solr_user_journal[{id}]
database /webmail/solr_user_journal[_]/entry_type = {null}

database SolrJournal.solr_contact /webmail/solr_contact_journal[{id}]
database /webmail/solr_contact_journal[_]/entry_type = {null}

module SolrJournal {

  private function debug(s) { Log.debug("[SolrJournal]", s) }
  private function info(s) { Log.info("[SolrJournal]", s) }
  private function notice(s) { Log.notice("[SolrJournal]", s) }
  private function error(s) { Log.error("[SolrJournal]", s) }

  function add_index(iom) {
    solr_mail = {id:iom.id, from:iom.from, to:iom.to, cc:iom.cc, bcc:iom.bcc, subject:iom.subject, content:iom.content,
                 date:iom.date, in:iom.in, owner:iom.owner, entry_type:{add}, journal_date:Date.now()}
    /webmail/solr_mail_journal[id == iom.id and owner == iom.owner] <- solr_mail
  }

  function remove_index(string id, string owner) {
    id = Message.midofs(id)
    solr_mail = ~{
      id, from:"",
      to:[], cc:[], bcc:[],
      subject:"", content:"",
      date:"", in:[], owner,
      entry_type:{remove},
      journal_date:Date.now()
    }
    /webmail/solr_mail_journal[id == id and owner == owner] <- solr_mail
  }

  function clear_index() {
    sms = Iter.to_list(DbSet.iterator(/webmail/solr_mail_journal.{id, owner}))
    List.iter(function (sm) { Db.remove(@/webmail/solr_mail_journal[id == sm.id, owner == sm.owner]) },sms)
  }

  function index() {
    recursive function aux(iter(SolrJournal.solr_mail) iter, successes) {
      match (iter.next()) {
      case {some:(solr_mail,iter)}:
        match (solr_mail.entry_type) {
        case {add}:
          //Ansi.jlog("SolrJournal.index: %yadd%d %b{solr_mail.id}%d %g{solr_mail.owner}%d")
          iom = {id:solr_mail.id, from:solr_mail.from, to:solr_mail.to, cc:solr_mail.cc, bcc:solr_mail.bcc,
                 subject:solr_mail.subject, content:solr_mail.content, date:solr_mail.date, in:solr_mail.in,
                 owner:solr_mail.owner}
          match (SolrMessage.index(iom)) {
          case {success:_}: aux(iter,[(solr_mail.id, solr_mail.owner,{add})|successes]);
          case {failure:_}: successes;
          };
        case {remove}:
          //Ansi.jlog("SolrJournal.index: %yremove%d %b{solr_mail.id}%d %g{solr_mail.owner}%d")
          match (SolrMessage.delete([("id","{solr_mail.id}"),("owner",solr_mail.owner)])) {
          case {success:_}: aux(iter,[(solr_mail.id, solr_mail.owner,{remove})|successes]);
          case {failure:_}: successes;
          };
        case {null}:
          aux(iter,[(solr_mail.id, solr_mail.owner,{null})|successes]);
        }
      case {none}: successes;
      }
    }
    successes = aux(DbSet.iterator(/webmail/solr_mail_journal),[])
    List.iter(function ((id,owner,entry_type)) {
                //Ansi.jlog("SolrJournal.index: delete %b{id}%d %c{owner}%d %m{entry_type}%d")
                Db.remove(@/webmail/solr_mail_journal[id == id, owner == owner, entry_type == entry_type])
              },successes)
  }

  function add_extract(id, name, mimetype) {
    //Ansi.jlog("SolrJournal.add_extract: file_id=%b{file_id}%d name=%c{name}%d")
    entry = ~{id, name, mimetype, entry_type:{add}, journal_date:Date.now()}
    /webmail/solr_file_journal[id == id] <- entry
  }

  function remove_extract(id) {
    entry = ~{id, name:"", mimetype:"", entry_type:{remove}, journal_date:Date.now()}
    /webmail/solr_file_journal[id == id] <- entry
  }

  function clear_extract() {
    sfs = Iter.to_list(DbSet.iterator(/webmail/solr_file_journal.{id}))
    List.iter(function (sf) {
                Db.remove(@/webmail/solr_file_journal[id == sf.id])
              },sfs)
  }

  function extract() {
    recursive function aux(iter(SolrJournal.solr_file) iter, successes) {
      match (iter.next()) {
      case {some:(solr_file,iter)}:
        match (solr_file.entry_type) {
        case {add}:
          //Ansi.jlog("SolrJournal.extract: %yadd%d %b{solr_file.file_id}%d %g{solr_file.name}%d")
          extra_fields = [("filename", solr_file.name)]
          content = Option.map(RawFile.getBytes, RawFile.get(solr_file.id)) ? Binary.create(0)
          match (SolrFile.extract(solr_file.id, content, solr_file.mimetype, extra_fields)) {
            case {success:_}: aux(iter,[(solr_file.id, {add})|successes]);
            case {failure:_}: successes;
          };
        case {remove}:
          //Ansi.jlog("SolrJournal.extract: %yremove%d %b{solr_file.file_id}%d %c{solr_file.history_file_id}%d")
          match (SolrFile.delete([("id",solr_file.id)])) {
          case {success:_}: aux(iter,[(solr_file.id, {remove})|successes]);
          case {failure:_}: successes;
          };
        case {null}:
          aux(iter,[(solr_file.id, {null})|successes])
        }
      case {none}: successes;
      }
    }
    successes = aux(DbSet.iterator(/webmail/solr_file_journal),[])
    List.iter(function ((id, entry_type)) {
                //Ansi.jlog("SolrJournal.extract: delete %b{file_id}%d %c{history_file_id}%d %m{entry_type}%d")
                Db.remove(@/webmail/solr_file_journal[id == id, entry_type == entry_type])
              },successes)
  }

  function add_census(iu) {
    //Ansi.jlog("add_census: iu=%c{iu}%d")
    solr_user = {id:iu.id, first_name:iu.first_name, last_name:iu.last_name, email:iu.email,
                 status:iu.status, level:iu.level, teams:iu.teams, sgn:iu.sgn,
                 entry_type:{add}, journal_date:Date.now()}
    /webmail/solr_user_journal[id == iu.id] <- solr_user
  }

  function remove_census(string id) {
    //Ansi.jlog("remove_census: id=%c{id}%d")
    solr_user = ~{id, first_name:"", last_name:"", email:"", status:"", level:0, teams:[], sgn:"",
                  entry_type:{remove}, journal_date:Date.now()}
    /webmail/solr_user_journal[id == id] <- solr_user
  }

  function clear_census() {
    sus = Iter.to_list(DbSet.iterator(/webmail/solr_user_journal.{id}))
    List.iter(function (su) { Db.remove(@/webmail/solr_user_journal[id == su.id]) },sus)
  }

  function census() {
    recursive function aux(iter(SolrJournal.solr_user) iter, successes) {
      match (iter.next()) {
      case {some:(solr_user,iter)}:
        match (solr_user.entry_type) {
        case {add}:
          //Ansi.jlog("SolrJournal.census: %yadd%d %b{solr_user.id}%d")
          iu = {id:solr_user.id, first_name:solr_user.first_name, last_name:solr_user.last_name, email:solr_user.email,
                status:solr_user.status, level:solr_user.level, teams:solr_user.teams, sgn:solr_user.sgn}
          match (SolrUser.index(iu)) {
          case {success:_}: aux(iter,[(solr_user.id, {add})|successes]);
          case {failure:_}: successes;
          };
        case {remove}:
          //Ansi.jlog("SolrJournal.census: %yremove%d %b{solr_user.id}%d")
          match (SolrUser.delete([("id","{solr_user.id}")])) {
          case {success:_}: aux(iter,[(solr_user.id, {remove})|successes]);
          case {failure:_}: successes;
          };
        case {null}:
          aux(iter,[(solr_user.id, {null})|successes]);
        }
      case {none}: successes;
      }
    }
    successes = aux(DbSet.iterator(/webmail/solr_user_journal),[])
    List.iter(function ((id,entry_type)) {
                //Ansi.jlog("SolrJournal.census: delete %b{id}%d %m{entry_type}%d")
                Db.remove(@/webmail/solr_user_journal[id == id, entry_type == entry_type])
              },successes)
  }

  function add_book(ic) {
    solr_contact = {
      id: ic.id,
      emails: ic.emails, owner: ic.owner,
      displayName: ic.displayName, /* name: ic.name, */ nickname: ic.nickname,
      blocked: ic.blocked,
      entry_type: {add}, journal_date: Date.now()
    }
    /webmail/solr_contact_journal[id == ic.id] <- solr_contact
  }

  function remove_book(string id, string owner) {
    //Ansi.jlog("remove_book: owner=%c{owner}%d email=%y{email}%d")
    solr_contact =
     ~{ id, owner, displayName: "",
        emails: [], nickname: "",
        blocked: "f",
        entry_type: {remove}, journal_date: Date.now() }
    /webmail/solr_contact_journal[id == id] <- solr_contact
  }

  function clear_book() {
    DbSet.iterator(/webmail/solr_contact_journal.{id, owner}) |>
    Iter.iter(function (sc) {
      Db.remove(@/webmail/solr_contact_journal[id == sc.id])
    }, _)
  }

  function book() {
    recursive function aux(iter(SolrJournal.solr_contact) iter, successes) {
      match (iter.next()) {
        case {some: (solr_contact,iter)}:
          match (solr_contact.entry_type) {
            case {add}:
              ic = {
                id: solr_contact.id,
                emails: solr_contact.emails, owner: solr_contact.owner,
                displayName: solr_contact.displayName, nickname: solr_contact.nickname,
                blocked: solr_contact.blocked
              }
              match (SolrContact.index(ic)) {
                case {success:_}: aux(iter, [(solr_contact.id, solr_contact.owner, {add})|successes])
                case {failure:_}: successes
              }
            case {remove}:
              match (SolrContact.delete([("id", solr_contact.id), ("owner", solr_contact.owner)])) {
                case {success:_}: aux(iter, [(solr_contact.id, solr_contact.owner, {remove})|successes])
                case {failure:_}: successes
              }
            case {null}:
              aux(iter, [(solr_contact.id, solr_contact.owner, {null})|successes])
          }
        case {none}: successes
      }
    }
    successes = aux(DbSet.iterator(/webmail/solr_contact_journal),[])
    List.iter(function ((id, owner, entry_type)) {
      Db.remove(@/webmail/solr_contact_journal[id == id, owner == owner, entry_type == entry_type])
    }, successes)
  }

  private function do_journal() {
    //Ansi.jlog("%rdo_journal%d")
    index()
    extract()
    census()
    book()
  }

  private timer = Scheduler.make_timer(AppConfig.solr_journal_timer, do_journal)

  function start_journal() {
    timer.start()
  }

  function stop_journal() {
    timer.stop()
  }

  function init() {
    // TODO: put init config in db
    start_journal()
  }

}

