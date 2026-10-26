local Adapter=require("mudlet_adapter")
local Display=require("who_display")

-- Entirely synthetic fixtures. Model native selections, replacement tails, and
-- format setters affecting both selected cells and the next scripted output.
local function copy(value)
  if type(value)~="table" then return value end
  local out={}; for key,item in pairs(value) do out[key]=copy(item) end
  return out
end
local function same(actual,expected)
  if type(expected)~="table" then eq(actual,expected); return end
  eq(type(actual),"table")
  for key,value in pairs(expected) do same(actual[key],value) end
  for key in pairs(actual) do assert(expected[key]~=nil,"unexpected field: "..tostring(key)) end
end
local function native(lines)
  local f={lines=copy(lines),cells={},cursor=10,column=4,replacements=0,writes=0,moves=0,resets=0,reads=0,forbidden=0}
  f.defaults={foreground={205,210,215},background={7,12,19},bold=false,underline=false}
  f.format={foreground={255,30,20},background={90,20,15},bold=true,underline=true}
  for row,line in pairs(f.lines) do
    f.cells[row]={}
    for index=1,#line do f.cells[row][index]=copy(f.format) end
  end
  local api={}
  api.getLineNumber=function() return f.cursor end
  api.getColumnNumber=function() return f.column end
  api.getBackgroundColor=function(window) eq(window,"main"); return 7,12,19,255 end
  api.getLines=function(first,last)
    eq(last,first+1); f.reads=f.reads+1
    return {f.lines[first]}
  end
  api.moveCursor=function(column,row)
    f.moves=f.moves+1; f.cursor=row; f.column=column; return true
  end
  api.selectSection=function(start,length)
    assert(f.lines[f.cursor],"selection outside main console")
    assert(start>=0 and length>=1 and start+length<=#f.lines[f.cursor],"selection outside native row")
    f.selected={row=f.cursor,start=start,length=length}
    f.column=start+length
    f.writes=f.writes+1
    return true
  end
  api.replace=function(text)
    local s=assert(f.selected,"replace requires native selection")
    eq(s.row,f.cursor)
    local before=f.lines[s.row]
    f.lines[s.row]=before:sub(1,s.start)..text..before:sub(s.start+s.length+1)
    local cells={}
    for index=1,s.start do cells[#cells+1]=copy(f.cells[s.row][index]) end
    for _=1,#text do cells[#cells+1]=copy(f.format) end
    for index=s.start+s.length+1,#before do cells[#cells+1]=copy(f.cells[s.row][index]) end
    f.cells[s.row]=cells
    f.replacements=f.replacements+1; f.writes=f.writes+1
  end
  local function paint(field,value)
    f.format[field]=copy(value)
    local s=assert(f.selected,"formatting must select the replacement")
    for index=s.start+1,s.start+s.length do
      assert(f.cells[s.row][index],"formatting outside replacement")[field]=copy(value)
    end
    f.writes=f.writes+1
  end
  api.setFgColor=function(r,g,b) paint("foreground",{r,g,b}) end
  api.setBgColor=function(r,g,b) paint("background",{r,g,b}) end
  api.setBold=function(value) paint("bold",value) end
  api.setUnderline=function(value) paint("underline",value) end
  api.deselect=function() f.selected=nil end
  api.resetFormat=function() f.resets=f.resets+1; f.format=copy(f.defaults); f.selected=nil end
  for _,name in ipairs({"echo","cecho","decho","hecho","insertText","deleteLine","send","sendAll",
      "appendBuffer","raiseEvent","postHTTP","downloadFile","writeFile","getBgColor"}) do
    api[name]=function() f.forbidden=f.forbidden+1; error("forbidden WHO side effect: "..name) end
  end
  local adapter=Adapter.new()
  adapter.settings={colorization={enabled=true,notice={bold=true,underline=true,background="#FF0000"}}}
  return f,api,adapter
end

local header="Room  Name  Username  Access  Rgn  IP Address"
local function source(room,name,account,access,ip)
  return room.."  "..name.."  "..account.."  "..access.."  1  "..ip
end
local function fixture()
  local lines={
    [0]="Synthetic room output",[2]=header,
    [4]=source("11","Synthetic Normal","fixture.normal","Normal","203.0.113.2"),
    [5]="    (Synthetic Copy) fixture.normal",
    [7]="Synthetic unrelated chat",
    [8]=source("12","Synthetic Admin Ten","fixture.ten","Admin","192.0.2.10"),
    [11]=source("13","Synthetic Sysop","fixture.sysop","Sysop","2001:db8::2"),
    [13]=source("14","Synthetic Admin Two","fixture.two","Admin","192.0.2.2"),
    [14]="You notice 4 adventurers.",[15]="Synthetic prompt>",
  }
  local items={}
  for _,slot in ipairs({4,8,11,13}) do
    items[#items+1]=assert(Display.parseRow(lines[slot]))
  end
  items[1].continuations={assert(Display.parseContinuation(lines[5]))}
  local formatted=assert(Display.formatRows(items))
  local rows={}
  for index,slot in ipairs({2,4,5,8,11,13}) do
    rows[index]={line_number=slot,source_line=lines[slot],display_text=formatted[index]}
  end
  local f,api,a=native(lines); f.cursor=15
  return f,api,a,rows
end
local function rejected(change)
  local f,api,a,rows=fixture(); change(rows,f,api)
  local before,cells,format=copy(f.lines),copy(f.cells),copy(f.format)
  local cursor,column=f.cursor,f.column
  local ok,err=a:replaceWhoOutput(rows,api)
  eq(ok,nil); eq(type(err),"string")
  same(f.lines,before); same(f.cells,cells); same(f.format,format)
  eq(f.writes,0); eq(f.moves,0); eq(f.replacements,0); eq(f.forbidden,0)
  eq(f.cursor,cursor); eq(f.column,column)
end

test("WHO trigger delegates its callback and trigger identity to colorizer",function()
  local a=Adapter.new(); local captured
  a.addColorizerTrigger=function(self,fn) eq(self,a); captured=fn; return 741 end
  local text,row
  local fn=function(value,number) text=value; row=number end
  eq(a:addWhoDisplayTrigger(fn),741); eq(captured,fn)
  captured(header,17); eq(text,header); eq(row,17)
end)

test("WHO native table preserves six aligned columns, owner continuation, footer and chat",function()
  local f,api,a,rows=fixture(); local before,cells=copy(f.lines),copy(f.cells)
  local shared=a.applyLineColors; local calls=0
  a.applyLineColors=function(self,segments,guarded)
    calls=calls+1; eq(#segments,#rows); return shared(self,segments,guarded)
  end
  assert(a:replaceWhoOutput(rows,api)); eq(calls,1); eq(f.replacements,6)
  for _,row in ipairs(rows) do
    eq(f.lines[row.line_number],row.display_text)
    for _,cell in ipairs(f.cells[row.line_number]) do
      same(cell,{foreground={220,224,220},background={7,12,19},bold=false,underline=false})
    end
  end
  eq(Display.parseRow(f.lines[4]).name,"Synthetic Sysop")
  eq(Display.parseRow(f.lines[5]).name,"Synthetic Admin Ten")
  eq(Display.parseRow(f.lines[8]).name,"Synthetic Admin Two")
  eq(Display.parseRow(f.lines[11]).name,"Synthetic Normal")
  eq(Display.parseContinuation(f.lines[13]).username,"fixture.normal")
  local nameAt=f.lines[2]:find("Name",1,true)
  local accountAt=f.lines[2]:find("Username",1,true)
  local accessAt=f.lines[2]:find("Access",1,true)
  local ipAt=f.lines[2]:find("IP Address",1,true)
  for _,slot in ipairs({4,5,8,11}) do
    local item=assert(Display.parseRow(f.lines[slot]))
    eq(f.lines[slot]:sub(nameAt,nameAt+#item.name-1),item.name)
    eq(f.lines[slot]:sub(accountAt,accountAt+#item.username-1),item.username)
    eq(f.lines[slot]:sub(accessAt,accessAt+#item.access-1),item.access)
    eq(f.lines[slot]:sub(ipAt),item.ip)
  end
  for _,slot in ipairs({0,7,14,15}) do eq(f.lines[slot],before[slot]); same(f.cells[slot],cells[slot]) end
  eq(f.cursor,15); eq(f.column,4); eq(f.selected,nil); same(f.format,f.defaults); eq(f.forbidden,0)
end)

test("WHO changed or shifted sources fail whole batch preflight before edits",function()
  for _,slot in ipairs({2,4,5,8,11,13}) do
    rejected(function(_,f) f.lines[slot]="Synthetic shifted chat" end)
  end
  rejected(function(_,f) f.lines[13]=f.lines[13]:gsub("192.0.2.2","192.0.2.3",1) end)
  rejected(function(_,f) f.lines[4]=" "..f.lines[4] end)
end)

test("WHO rejects invalid header, record, coordinates and continuation ownership",function()
  for _,value in ipairs({-1,0,2,1.5,math.huge,0/0,"4"}) do
    rejected(function(rows) rows[2].line_number=value end)
  end
  for _,value in ipairs({"Name  Race  Class", "Room  Name  Username  Access  IP Address"}) do
    rejected(function(rows,f) rows[1].source_line=value; f.lines[2]=value end)
  end
  for _,value in ipairs({
    "11 Synthetic Normal fixture.normal Normal 1 203.0.113.2",
    "11  Synthetic#Invalid  fixture.normal  Normal 1 203.0.113.2",
    header,"You notice 4 adventurers.",
  }) do
    rejected(function(rows,f) rows[2].source_line=value; f.lines[4]=value end)
  end
  rejected(function(rows,f)
    rows[2].source_line="  (Orphan Copy) fixture.normal"; f.lines[4]=rows[2].source_line
  end)
  rejected(function(rows,f)
    rows[3].source_line="  (Foreign Copy) fixture.other"; f.lines[5]=rows[3].source_line
  end)
  rejected(function(rows) rows[3].remove=true end)
end)

test("WHO rejects malformed fields and bounded or sparse batches without mutation",function()
  for _,value in ipairs({"",false,{},string.rep("X",257),"Name\tUsername","<red>WHO","WHO\n","WHO"..string.char(128)}) do
    rejected(function(rows) rows[6].display_text=value end)
  end
  for _,suffix in ipairs({"\n","\r","\0","\27[31m","<red>",string.char(127),string.char(128)}) do
    rejected(function(rows,f) rows[2].source_line=rows[2].source_line..suffix; f.lines[4]=rows[2].source_line end)
  end
  rejected(function(rows) rows[2].source_line=string.rep("X",513) end)
  rejected(function(rows) rows[3]=nil end)
  rejected(function(rows) rows.extra=true end)
  rejected(function(rows) setmetatable(rows[2],{__index=function() error("unexpected metatable") end}) end)
  rejected(function(rows) for index=7,1538 do rows[index]=copy(rows[6]) end end)
end)

test("WHO requires every native replacement API before any edit",function()
  for _,key in ipairs({"getLines","getLineNumber","getColumnNumber","getBackgroundColor","moveCursor",
      "selectSection","replace","setFgColor","setBgColor","setBold","setUnderline","deselect","resetFormat"}) do
    rejected(function(_,_,api) api[key]=nil end)
  end
end)

test("WHO native failures report errors and attempt cursor and format cleanup",function()
  for _,key in ipairs({"moveCursor","selectSection","replace","setFgColor","setBgColor","setBold","setUnderline","resetFormat"}) do
    local f,api,a,rows=fixture(); local original=api[key]; local failed=false
    api[key]=function(...)
      if not failed then
        failed=true
        if key=="setFgColor" or key=="resetFormat" then error("synthetic native failure") end
        return false,"synthetic native failure"
      end
      return original(...)
    end
    local ok,err=a:replaceWhoOutput(rows,api)
    eq(ok,nil); eq(type(err),"string")
    eq(f.cursor,15); eq(f.column,4); eq(f.selected,nil); same(f.format,f.defaults); eq(f.forbidden,0)
    if key=="moveCursor" or key=="selectSection" or key=="replace" then eq(f.replacements,0) end
  end
  for _,key in ipairs({"getLines","getLineNumber","getColumnNumber","getBackgroundColor"}) do
    rejected(function(_,_,api) api[key]=function() error("synthetic read failure") end end)
  end
end)

test("WHO detects a source change at renderer recheck instead of silently skipping",function()
  local f,api,a,rows=fixture(); local get=api.getLines; local reads=0
  api.getLines=function(first,last)
    reads=reads+1
    if reads==#rows+1 then f.lines[2]="Synthetic replacement chat" end
    return get(first,last)
  end
  local ok,err=a:replaceWhoOutput(rows,api)
  eq(ok,nil); assert(err:find("WHO source row changed",1,true))
  eq(f.replacements,0); eq(f.lines[2],"Synthetic replacement chat"); eq(f.cursor,15); eq(f.column,4)
end)

test("WHO tabbed sources and trailing padding replace complete native rows and preserve current cursor",function()
  local line="12\t\tSynthetic Tab\t\tfixture.tab\tHead-GM\t1\t198.51.100.2\t"
  local item=assert(Display.parseRow(line)); local output=assert(Display.formatRows({item}))
  local lines={[1]="Room\tName\tUsername\tAccess\tRgn\tIP Address  ",[2]=line.."   ",[3]="You notice 1 adventurer."}
  local f,api,a=native(lines); f.cursor=2; f.column=7
  assert(a:replaceWhoOutput({
    {line_number=1,source_line=lines[1],display_text=output[1]},
    {line_number=2,source_line=line,display_text=output[2]},
  },api))
  eq(f.lines[1],output[1]); eq(f.lines[2],output[2]); eq(#f.cells[2],#output[2])
  eq(f.lines[3],lines[3]); eq(f.cursor,2); eq(f.column,7); same(f.format,f.defaults); eq(f.forbidden,0)
end)

test("WHO header-only batch leaves its zero-record footer unchanged",function()
  local f,api,a=native({[0]=header,[1]="You notice 0 adventurers."})
  local footer=copy(f.cells[1])
  assert(a:replaceWhoOutput({{line_number=0,source_line=header,display_text=Display.formatRows({})[1]}},api))
  eq(f.replacements,1); eq(f.lines[1],"You notice 0 adventurers."); same(f.cells[1],footer)
  eq(f.cursor,10); eq(f.column,4); eq(f.forbidden,0)
end)
