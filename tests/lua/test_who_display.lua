local Display=require("who_display")
local HEADER=" Room  Name                             Username             Access     Rgn  IP Address"
local function record(index,access,ip)
  return {room=tostring(100+index),name="Synthetic "..index,username="fixture_"..index,
    access=access or "Normal",region="1",ip=ip or ("192.0.2."..index)}
end
local function raw(item)
  return string.format("%5s  %-30s  %-20s  %-10s  %3s  %s",
    item.room,item.name,item.username,item.access,item.region,item.ip)
end
local function continuation(label,user) return "      ("..label.."   ) "..user end
local function count(values) local n=0; for _ in pairs(values) do n=n+1 end; return n end
local function parsedRecords(lines)
  local rows={}; assert(Display.isHeader(lines[1]))
  for index=2,#lines do local item=Display.parseRow(lines[index]); if item then rows[#rows+1]=item end end
  return rows
end
local function aligned(lines)
  local header=lines[1]
  for _,line in ipairs(lines) do
    local item=Display.parseRow(line)
    if item then
      for _,field in ipairs({{"name","Name"},{"username","Username"},{"access","Access"},{"ip","IP Address"}}) do
        eq(line:find(item[field[1]],1,true),header:find(field[2],1,true))
      end
    end
  end
end
local function fake(start)
  local f={next=0,events={},triggers={},timers={},history={},batches={},lines={},clock=0}
  function f:addWhoDisplayTrigger(fn)
    if self.failTrigger then return nil,"synthetic trigger failure" end
    self.next=self.next+1; self.trigger=fn; self.triggers[self.next]=fn; return self.next
  end
  function f:killTrigger(id) self.triggers[id]=nil end
  function f:addEvent(event,fn) self.next=self.next+1; self.events[self.next]={event=event,fn=fn}; return self.next end
  function f:killEvent(id) self.events[id]=nil end
  function f:emit(event,...)
    local handlers={}; for _,entry in pairs(self.events) do if entry.event==event then handlers[#handlers+1]=entry.fn end end
    for _,fn in ipairs(handlers) do fn(...) end
  end
  function f:schedule(delay,fn)
    self.next=self.next+1; local timer={delay=delay,at=self.clock+delay,fn=fn}
    self.timers[self.next]=timer; self.history[#self.history+1]=timer; return self.next
  end
  function f:cancelTimer(id) self.timers[id]=nil end
  function f:advance(seconds)
    self.clock=self.clock+seconds
    local ready={}; for id,timer in pairs(self.timers) do if timer.at<=self.clock then ready[#ready+1]=id end end
    table.sort(ready)
    for _,id in ipairs(ready) do local timer=self.timers[id]; if timer then self.timers[id]=nil; timer.fn() end end
  end
  function f:replaceWhoOutput(rows) self.batches[#self.batches+1]=rows; return true end
  for _,method in ipairs({"sendCommand","send","saveSettings","saveChatSettings","appendChat","createChatStorage","submitFeedback","downloadFile"}) do
    f[method]=function() error("WHO attempted a forbidden side effect") end
  end
  local d=Display.new(f,"SyntheticHUD")
  function f:feed(text,row)
    if type(row)=="number" and row==row then self.lines[row]=text end
    return self.trigger(text,row)
  end
  if start~=false then assert(d:start()) end
  return f,d
end
local function begin(f,d)
  f:emit("sysDataSendRequest","sysDataSendRequest","who"); f:feed(HEADER,10)
end
local function complete(f,d)
  begin(f,d); f:feed(raw(record(1)),11); f:feed("You notice 1 adventurer.",12)
end
local function late(f) for _,timer in ipairs(f.history) do timer.fn() end end
local function untouched(f) eq(#f.batches,0); eq(next(f.timers),nil) end

test("WHO accepts exact case-insensitive who and who all commands including alias expansions",function()
  for _,value in ipairs({"who"," WHO ","\tWhO\t","who all"," WHO ALL ","\tWhO\t AlL\t"}) do eq(Display.isCommand(value),true) end
  for _,value in ipairs({"who fixture","who all extra","whoall","who;look","who all;look","who all\nlook",
      "who\nlook","who\r","who\0","who all\r","> who","say who","whom","",string.rep(" ",33).."who",false,42,{}}) do
    eq(Display.isCommand(value),false)
  end
  eq(Display.isCommand(nil),false)
end)

test("WHO strict six-column header and full rows parse without exposing real identities",function()
  assert(Display.isHeader(HEADER)); assert(Display.isHeader("\27[32m"..HEADER.."\27[0m\7\r\n"))
  for _,value in ipairs({"Name Username Access","Room Name Username Access Rgn IP Address Extra","Name Race Profession",""}) do
    eq(Display.isHeader(value),false)
  end
  local item=record(1,"Head-GM","2001:db8::1")
  local parsed=assert(Display.parseRow("\27[32m"..raw(item).."\27[0m\7\r\n"))
  for _,field in ipairs({"room","name","username","access","region","ip"}) do eq(parsed[field],item[field]); eq(type(parsed[field]),"string") end
end)

test("WHO continuation parsing trims labels and requires a complete account field",function()
  local value=assert(Display.parseContinuation(continuation("Synthetic Companions","fixture_1")))
  eq(value.label,"Synthetic Companions"); eq(value.username,"fixture_1")
  for _,text in ipairs({"(No indent) fixture_1","      () fixture_1","      (Label)","      (Label) fixture_1 extra",
      "      (<Label>) fixture_1","      (Label) fixture_1\ninjected"}) do eq(Display.parseContinuation(text),nil) end
end)

test("WHO addresses validate documentation IPv4 and expand IPv6 into numeric components",function()
  local v4=assert(Display.parseAddress("192.0.2.10")); eq(v4.family,4); eq(#v4.parts,4)
  for index,value in ipairs({192,0,2,10}) do eq(v4.parts[index],value) end
  for _,ip in ipairs({"2001:db8::2","2001:0DB8:0:0:0:0:0:0002"}) do
    local v6=assert(Display.parseAddress(ip)); eq(v6.family,6); eq(#v6.parts,8)
    for index,value in ipairs({8193,3512,0,0,0,0,0,2}) do eq(v6.parts[index],value) end
  end
  for _,ip in ipairs({"192.0.2.256","192.0.2","192.0.2.-1","192.0.2.2:80","2001:db8:::1",
      "2001:db8::1::2","2001:db8:0:0:0:0:0:10000","2001:db8::g","2001:db8::1%eth0","[2001:db8::1]","hostname.example"}) do
    eq(Display.parseAddress(ip),nil)
  end
end)

test("WHO access precedence retains unknown levels alphabetically before Normal",function()
  local roles={"Normal","Zeta","Supporter","Designer","GM","Admin","Sysop","alpha","Head-GM"}
  local items={}; for index,role in ipairs(roles) do items[index]=record(index,role) end
  local rows=parsedRecords(assert(Display.formatRows(items)))
  for index,role in ipairs({"Sysop","Admin","GM","Designer","Supporter","alpha","Head-GM","Zeta","Normal"}) do eq(rows[index].access,role) end
  local folded={record(1,"gM","192.0.2.10"),record(2,"GM","192.0.2.2"),record(3,"Observer","192.0.2.10"),record(4,"observer","192.0.2.2")}
  local sorted=parsedRecords(assert(Display.formatRows(folded)))
  eq(sorted[1].username,"fixture_1"); eq(sorted[2].username,"fixture_2")
  eq(sorted[3].username,"fixture_3"); eq(sorted[4].username,"fixture_4")
end)

test("WHO sorts room numbers numerically within access regardless of IP and keeps same-room ties stable",function()
  local ips={"2001:db8::10","192.0.2.10","2001:db8::2","2001:0db8:0:0:0:0:0:0002","192.0.2.2","2001:db8::9"}
  local rooms={"100","10","2","0002","0","9999999999"}
  local items={}; for index,ip in ipairs(ips) do items[index]=record(index,"GM",ip); items[index].room=rooms[index] end
  local rows=parsedRecords(assert(Display.formatRows(items)))
  for index,original in ipairs({5,3,4,2,1,6}) do eq(rows[index].username,items[original].username); eq(rows[index].ip,ips[original]) end
  for index,item in ipairs(items) do eq(item.room,rooms[index]) end
  local first,second=record(2,"Normal","2001:db8::10"),record(1,"Normal","192.0.2.1")
  first.room="777"; second.room="777"
  local tied=parsedRecords(assert(Display.formatRows({first,second})))
  eq(tied[1].username,"fixture_2"); eq(tied[2].username,"fixture_1")
end)

test("WHO formatting aligns six columns keeps continuations with owners and preserves input",function()
  local first=record(1,"Normal","203.0.113.10"); first.continuations={{label="Synthetic Companions",username=first.username}}
  local second=record(2,"Admin","2001:db8::1"); second.name="Synthetic Longer Name"
  local items={first,second}; local attached=first.continuations
  local lines=assert(Display.formatRows(items)); eq(#lines,4); aligned(lines)
  eq(assert(Display.parseRow(lines[2])).username,second.username)
  eq(assert(Display.parseRow(lines[3])).username,first.username)
  eq(assert(Display.parseContinuation(lines[4])).username,first.username)
  eq(items[1],first); eq(items[2],second); eq(first.continuations,attached); eq(first.continuations[1].label,"Synthetic Companions")
end)

test("WHO 33 synthetic records defer one guarded rewrite while preserving footer and attached lines",function()
  local f,d=fake(); f:emit("sysDataSendRequest","sysDataSendRequest"," WHO ")
  f:feed("Full who list activated!",1); f:feed("A synthetic bell rings.",2); f:feed(HEADER,100)
  local row=101
  for index=1,33 do
    local item=record(index,"Normal","192.0.2."..index); item.room=tostring(34-index)
    f:feed(raw(item),row); row=row+1
    if index==18 then f:feed(continuation("Synthetic Companions",item.username),row); row=row+1 end
  end
  f:feed("You notice 33 adventurers.",row); eq(#f.batches,0); eq(count(f.timers),1)
  local _,timer=next(f.timers); eq(timer.delay,0); f:advance(0)
  eq(#f.batches,1); eq(next(f.timers),nil); local batch=f.batches[1]; eq(#batch,35)
  local lines={}
  for index,slot in ipairs(batch) do
    eq(slot.line_number,99+index); eq(slot.source_line,f.lines[slot.line_number]); eq(slot.remove,nil)
    assert(slot.line_number<row); lines[index]=slot.display_text
  end
  aligned(lines); local rows=parsedRecords(lines); eq(#rows,33)
  for index,item in ipairs(rows) do eq(item.username,"fixture_"..(34-index)) end
  for index,line in ipairs(lines) do
    local attached=Display.parseContinuation(line)
    if attached then eq(attached.username,"fixture_18"); eq(assert(Display.parseRow(lines[index-1])).username,attached.username) end
  end
  eq(f.lines[row],"You notice 33 adventurers."); d:shutdown()
end)

test("WHO refuses unsolicited tables and public or missing staff headers",function()
  for _,command in ipairs({false,"who","who fixture"}) do
    local f,d=fake(); if command then d:onOutgoing(command) end
    if command~= "who" then f:feed(HEADER,10) else f:feed("Name Race Profession",10) end
    f:feed(raw(record(1)),11); f:feed("You notice 1 adventurer.",12); f:advance(0); late(f); untouched(f); d:shutdown()
  end
end)

test("WHO ALL and alias-expanded WHO requests format exactly one complete staff report",function()
  for _,commands in ipairs({{"who all"},{" WHO\tALL "},{"who","who all"}}) do
    local f,d=fake()
    for _,command in ipairs(commands) do f:emit("sysDataSendRequest","sysDataSendRequest",command) end
    f:feed(HEADER,10); f:feed(raw(record(1,"Normal")),11); f:feed(raw(record(2,"GM")),12)
    f:feed("You notice 2 adventurers.",13); f:advance(0); late(f)
    eq(#f.batches,1); eq(#f.batches[1],3)
    eq(assert(Display.parseRow(f.batches[1][2].display_text)).access,"GM")
    eq(f.lines[13],"You notice 2 adventurers."); d:shutdown()
  end
end)

test("WHO ALL still requires a complete validated staff header and matching footer",function()
  for _,mode in ipairs({"public","missing","count","malformed"}) do
    local f,d=fake(); d:onOutgoing("who all")
    if mode=="public" then f:feed("Name Race Profession",10)
    elseif mode~="missing" then f:feed(HEADER,10) end
    f:feed(raw(record(1)),11)
    if mode=="malformed" then f:feed("100  Broken WHO row",12) end
    f:feed(mode=="count" and "You notice 2 adventurers." or "You notice 1 adventurer.",13)
    f:advance(0); late(f); untouched(f); d:shutdown()
  end
end)

test("WHO malformed rows continuation owners headers and footer counts leave the full report raw",function()
  local broken=record(2); broken.ip="192.0.2.999"
  local hashName=record(2); hashName.name="Synthetic#Name"
  for _,value in ipairs({raw(broken),raw(hashName),continuation("Synthetic","other_fixture"),HEADER,
      "You notice 2 adventurers.","You notice 1 adventurers. extra","You notice # adventurers."}) do
    local f,d=fake(); begin(f,d); f:feed(raw(record(1)),11); f:feed(value,12)
    f:feed("You notice 1 adventurer.",13); f:advance(0); late(f); untouched(f); d:shutdown()
  end
end)

test("WHO incomplete reports expire after five seconds without refreshing the deadline",function()
  local f,d=fake(); begin(f,d); f:advance(4); f:feed(raw(record(1)),11); f:advance(1)
  f:feed("You notice 1 adventurer.",12); f:advance(0); untouched(f); d:shutdown()
  local f2,d2=fake(); begin(f2,d2); f2:feed(raw(record(1)),11); f2:feed(">",12); late(f2); untouched(f2); d2:shutdown()
end)

test("WHO bounded input rejects oversized lines row overflow duplicate positions and excess attachments",function()
  eq(Display.MAX_ROWS,512); eq(Display.MAX_LINES,2048); eq(Display.MAX_LINE_BYTES,512); eq(Display.MAX_CONTINUATIONS,2); eq(Display.RESPONSE_TIMEOUT,5)
  for _,mode in ipairs({"bytes","rows","lines","coordinate","continuations"}) do
    local f,d=fake(); begin(f,d)
    if mode=="bytes" then f:feed(string.rep("x",513),11)
    elseif mode=="rows" then for index=1,513 do f:feed(raw(record(index,"Normal","192.0.2.1")),10+index) end
    elseif mode=="lines" then for index=1,2049 do f:feed("",10+index) end
    elseif mode=="coordinate" then f:feed(raw(record(1)),10)
    else
      f:feed(raw(record(1)),11)
      for index=1,3 do f:feed(continuation("Synthetic "..index,"fixture_1"),11+index) end
    end
    f:feed("You notice 1 adventurer.",3000); f:advance(0); late(f); untouched(f); d:shutdown()
  end
end)

test("WHO new outgoing commands invalidate old generations and blank nudges remain passive",function()
  local f,d=fake(); complete(f,d); local stale=assert(f.timers[d.timer]).fn
  d:onOutgoing("look"); stale(); untouched(f)
  d:onOutgoing("WHO"); f:feed(HEADER,20); f:feed(raw(record(2)),21); d:onOutgoing(" \t")
  f:feed("You notice 1 adventurer.",22); stale(); f:advance(0); eq(#f.batches,1)
  eq(f.batches[1][1].line_number,20); d:shutdown()
end)

test("WHO disconnect package menu shutdown and explicit cancel retire pending callbacks",function()
  for _,boundary in ipairs({"disconnect","install","uninstall","menu","shutdown","cancel"}) do
    local f,d=fake(); complete(f,d)
    if boundary=="disconnect" then f:emit("sysDisconnectionEvent")
    elseif boundary=="install" then f:emit("sysInstallPackage","sysInstallPackage","SyntheticHUD")
    elseif boundary=="uninstall" then f:emit("sysUninstallPackage","sysUninstallPackage","SyntheticHUD")
    elseif boundary=="menu" then f:feed("Dragon's Gate Menu",13)
    else d[boundary](d) end
    late(f); untouched(f); d:shutdown()
  end
end)

test("WHO startup is passive idempotent and shutdown cleans only owned resources",function()
  local f,d=fake(false); local personal=f:addEvent("personal",function() end); f.triggers.personal=function() end
  assert(d:start()); local nextId=f.next; assert(d:start()); eq(f.next,nextId); eq(#f.history,0)
  complete(f,d); d:shutdown(); late(f); untouched(f); eq(count(f.events),1); assert(f.events[personal]); eq(count(f.triggers),1)
  local broken,display=fake(false); broken.failTrigger=true; assert(not display:start()); display:shutdown()
  eq(next(broken.events),nil); eq(next(broken.triggers),nil)
end)
