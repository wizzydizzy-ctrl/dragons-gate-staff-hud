local Base=require("wealth_display")
local Parser=require("command_parser")
local Display=setmetatable({}, {__index=Base}); Display.__index=Display
Display.MAX_ROWS=512; Display.MAX_LINES=2048; Display.MAX_LINE_BYTES=512
Display.MAX_CONTINUATIONS=2; Display.RESPONSE_TIMEOUT=5
local accessOrder={sysop=1,admin=2,gm=3,designer=4,supporter=5,normal=7}
local function clean(value)
  if type(value)~="string" or #value>Display.MAX_LINE_BYTES then return nil end
  local text=value:gsub("\27%[[0-?]*[ -/]*[@-~]",""):gsub("\7","")
  if text:sub(-1)=="\n" then text=text:gsub("\r?\n$","") else text=text:gsub("\r$","") end
  if text:find("[\r\n%z]") or text:find("[\1-\8\11\12\14-\31\127]") then return nil end
  return text
end
local function trim(value) return value:match("^%s*(.-)%s*$") end
local function coordinate(value)
  return type(value)=="number" and value==value and value>=0 and value<math.huge and value%1==0
end
local function username(value)
  return type(value)=="string" and #value<=64 and value:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")~=nil
end
local function name(value)
  return type(value)=="string" and #value<=80 and value:match("^[A-Za-z][A-Za-z0-9_%-' ]*$")~=nil
end
local function digits(value)
  return type(value)=="string" and #value<=10 and value:match("^%d+$")~=nil
end
local function access(value)
  return type(value)=="string" and #value<=24 and value:match("^[A-Za-z][A-Za-z0-9_%-]*$")~=nil
end
local function ipv4(value)
  local a,b,c,d=value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  local parts={a,b,c,d}
  for i,part in ipairs(parts) do
    if #part>3 or tonumber(part)>255 then return nil end
    parts[i]=tonumber(part)
  end
  return parts
end
function Display.parseAddress(value)
  if type(value)~="string" or #value>45 or not value:match("^[%x:%.]+$") then return nil end
  if not value:find(":",1,true) then
    local parts=ipv4(value); return parts and {family=4,parts=parts} or nil
  end
  local text=value
  if text:find(".",1,true) then
    local prefix,tail=text:match("^(.-):([%d%.]+)$")
    local octets=tail and ipv4(tail)
    if not prefix or not octets then return nil end
    text=prefix..":"..string.format("%x:%x",octets[1]*256+octets[2],octets[3]*256+octets[4])
  end
  local function hextets(part)
    if part=="" then return {} end
    if part:sub(1,1)==":" or part:sub(-1)==":" or part:find("::",1,true) then return nil end
    local result={}
    for token in part:gmatch("[^:]+") do
      if #token>4 or not token:match("^%x+$") then return nil end
      result[#result+1]=tonumber(token,16)
    end
    return result
  end
  local at=text:find("::",1,true)
  local parts
  if at then
    local left,right=hextets(text:sub(1,at-1)),hextets(text:sub(at+2))
    if not left or not right or #left+#right>=8 then return nil end
    parts=left
    local zeros=8-#left-#right
    for _=1,zeros do parts[#parts+1]=0 end
    for _,part in ipairs(right) do parts[#parts+1]=part end
  else
    parts=hextets(text); if not parts or #parts~=8 then return nil end
  end
  return {family=6,parts=parts}
end
function Display.isCommand(value)
  return type(value)=="string" and #value<=32 and not value:find("[^\t -~]")
    and value:lower():match("^[ \t]*who[ \t]*$")~=nil
end
function Display.isHeader(value)
  local text=clean(value)
  return text~=nil and text:match("^%s*Room%s+Name%s+Username%s+Access%s+Rgn%s+IP%s+Address%s*$")~=nil
end
function Display.parseRow(value)
  local text=clean(value); if not text then return nil end
  local room,full,account,role,region,ip=text:match("^%s*(%d+)%s%s+(.-)%s%s+(%S+)%s+(%S+)%s+(%d+)%s+(%S+)%s*$")
  if not room then return nil end
  full=trim(full):gsub(" +"," ")
  if not digits(room) or not name(full) or not username(account) or not access(role)
      or not digits(region) or not Display.parseAddress(ip) then return nil end
  return {room=room,name=full,username=account,access=role,region=region,ip=ip}
end
function Display.parseContinuation(value)
  local text=clean(value); if not text then return nil end
  local label,account=text:match("^%s+%((.-)%)%s+([A-Za-z0-9_.%-]+)%s*$")
  if not label then return nil end
  label=trim(label)
  if #label==0 or #label>80 or label:find("[^ -~]") or label:find("[<>()]") or not username(account) then return nil end
  return {label=label,username=account}
end
function Display.formatRows(items)
  if type(items)~="table" or #items>Display.MAX_ROWS then return nil,"Invalid WHO report." end
  local sorted={}; local widths={4,4,8,6,3,10}
  local function measure(values)
    for i,value in ipairs(values) do widths[i]=math.max(widths[i],#value) end
  end
  for index,item in ipairs(items) do
    if type(item)~="table" or not digits(item.room) or not name(item.name) or not username(item.username)
        or not access(item.access)
        or not digits(item.region) then return nil,"Invalid WHO record." end
    local key=Display.parseAddress(item.ip); if not key then return nil,"Invalid WHO address." end
    local row={item.room,item.name,item.username,item.access,item.region,item.ip}
    local entry={row=row,key=key,access=item.access:lower(),index=index,continuations={}}
    measure(row)
    local attached=item.continuations or {}
    if type(attached)~="table" or #attached>Display.MAX_CONTINUATIONS then return nil,"Invalid WHO continuation." end
    for _,value in ipairs(attached) do
      if type(value)~="table" or type(value.label)~="string" or not username(value.username)
          or value.username:lower()~=item.username:lower() then return nil,"Invalid WHO continuation." end
      local checked=Display.parseContinuation(" ("..value.label..") "..value.username)
      if not checked then return nil,"Invalid WHO continuation." end
      local continuation={"","("..checked.label..")",checked.username,"","",""}
      entry.continuations[#entry.continuations+1]=continuation; measure(continuation)
    end
    sorted[#sorted+1]=entry
  end
  table.sort(sorted,function(a,b)
    local rankA,rankB=accessOrder[a.access] or 6,accessOrder[b.access] or 6
    if rankA~=rankB then return rankA<rankB end
    if a.access~=b.access then return a.access<b.access end
    if a.key.family~=b.key.family then return a.key.family<b.key.family end
    for i,part in ipairs(a.key.parts) do if part~=b.key.parts[i] then return part<b.key.parts[i] end end
    return a.index<b.index
  end)
  local function columns(values)
    local last=#values
    while last>1 and values[last]=="" do last=last-1 end
    local cells={}
    for i=1,last do
      local value=values[i]; local padding=string.rep(" ",widths[i]-#value)
      cells[i]=(i==1 or i==5) and padding..value or (i<last and value..padding or value)
    end
    return table.concat(cells,"  ")
  end
  local lines={columns({"Room","Name","Username","Access","Rgn","IP Address"})}
  for _,entry in ipairs(sorted) do
    lines[#lines+1]=columns(entry.row)
    for _,value in ipairs(entry.continuations) do lines[#lines+1]=columns(value) end
  end
  return lines
end
function Display.new(adapter,packageName)
  return setmetatable(Base.new(adapter,packageName),Display)
end
function Display:onOutgoing(command)
  if not self.started then return false end
  if type(command)=="string" and command:match("^[ \t]*$") then return false end
  self:cancel()
  if not Display.isCommand(command) then return false end
  self.response={rows={},slots={},numbers={},lines=0}
  return self:armTimer(Display.RESPONSE_TIMEOUT,function() self:cancel() end)==true
end
function Display:addSlot(source,number)
  local response=self.response; local previous=response.slots[#response.slots]
  if not coordinate(number) or response.numbers[number] or (previous and number<=previous.line_number) then return nil end
  response.numbers[number]=true
  response.slots[#response.slots+1]={source_line=source,line_number=number}
  return true
end
function Display:finish(total,number)
  local response=self.response; local previous=response.slots[#response.slots]
  if not response.header or #total>3 or tonumber(total)~=#response.rows or not previous
      or not coordinate(number) or number<=previous.line_number then self:cancel(); return false end
  local formatted=Display.formatRows(response.rows)
  if not formatted or #formatted~=#response.slots then self:cancel(); return false end
  local pending=response.slots
  for i,row in ipairs(pending) do row.display_text=formatted[i] end
  self:cancel(); self.pending=pending
  return self:armTimer(0,function()
    local rows=self.pending; self.pending=nil
    if self.started and rows then pcall(self.adapter.replaceWhoOutput,self.adapter,rows) end
  end)==true
end
function Display:onLine(value,number)
  if not self.started or (not self.response and not self.pending) then return false end
  local source=clean(value); if not source then self:cancel(); return false end
  local text=trim(source)
  if text=="Dragon's Gate Menu" or text:find("Dragon's Gate Character Creator",1,true)
      or text:match("^Welcome to Dragon's Gate,") then self:cancel(); return false end
  local response=self.response; if not response then return false end
  response.lines=response.lines+1
  if response.lines>Display.MAX_LINES then self:cancel(); return false end
  if Display.isHeader(source) then
    if response.header or not self:addSlot(source,number) then self:cancel(); return false end
    response.header=true; return true
  end
  local total=text:match("^You notice (%d+) adventurers?%.$")
  if total then return self:finish(total,number) end
  if Parser.isPrompt(source) then self:cancel(); return false end
  if not response.header then return false end
  local item=Display.parseRow(source)
  if item then
    if #response.rows>=Display.MAX_ROWS or not self:addSlot(source,number) then self:cancel(); return false end
    item.continuations={}; response.rows[#response.rows+1]=item; return true
  end
  local continuation=Display.parseContinuation(source)
  if continuation then
    local owner=response.rows[#response.rows]
    if not owner or owner.username:lower()~=continuation.username:lower()
        or #owner.continuations>=Display.MAX_CONTINUATIONS or not self:addSlot(source,number) then self:cancel(); return false end
    owner.continuations[#owner.continuations+1]=continuation; return true
  end
  if text:match("^%d") or text:match("^%(") or text:match("^You notice ") then self:cancel() end
  return false
end
function Display:start()
  if self.started then return true end
  for _,key in ipairs({"addWhoDisplayTrigger","replaceWhoOutput","addEvent","killEvent","killTrigger","schedule","cancelTimer"}) do
    if type(self.adapter[key])~="function" then return nil,"WHO display is unavailable in this adapter." end
  end
  local ok,id=pcall(self.adapter.addWhoDisplayTrigger,self.adapter,function(value,number)
    if not pcall(self.onLine,self,value,number) then self:cancel() end
  end)
  if not ok or not id then return nil,"WHO display trigger registration failed." end
  self.trigger=id; self.started=true
  local function watch(event,fn)
    local called,handler=pcall(self.adapter.addEvent,self.adapter,event,fn)
    if not called or not handler then self:shutdown(); return nil end
    self.events[#self.events+1]=handler; return true
  end
  if not watch("sysDataSendRequest",function(_,command) self:onOutgoing(command) end)
      or not watch("sysDisconnectionEvent",function() self:cancel() end)
      or not watch("sysInstallPackage",function(_,package) if package==self.package_name then self:cancel() end end)
      or not watch("sysUninstallPackage",function(_,package) if package==self.package_name then self:cancel() end end) then
    return nil,"WHO display event registration failed."
  end
  return true
end
return Display
