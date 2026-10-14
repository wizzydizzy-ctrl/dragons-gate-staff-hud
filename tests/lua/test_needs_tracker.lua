local Needs=require("needs_tracker")
test("independent self identity guards direct and wrapped foreign INFO needs",function()
  local parser=require("command_parser")
  local own=[[You are Synthetic Tester, a light boned and muscular bodied 57 year old Entropic Male young Elder. You are 7'7" and weigh 239 lbs.]]
  for _,identity in ipairs({"Synthetic","Synthetic Tester",{name="Synthetic",full_name="Synthetic Tester"},
      {name="Synthetic",surname="Tester"}}) do
    local changes=0
    local n=Needs.new({epoch=function() return 42 end},function() changes=changes+1 end,function() return identity end)
    assert(n:onLine("You are ravenous. You are parched.")); local before=n:status()
    local foreign={own:gsub("Synthetic Tester","Other Tester"),"You are satiated.","Your thirst is quenched.",">"}
    assert(parser.parseInfo(foreign)); eq(n:onInfo(parser.parseInfo(foreign)),false)
    for index,line in ipairs(foreign) do eq(n:onLine("\27[32m"..(index==1 and "> " or "")..line.."\27[0m"),false) end
    for _,need in ipairs({"hunger","thirst"}) do
      for _,field in ipairs({"status","timestamp","source","raw"}) do eq(n:status()[need][field],before[need][field]) end
    end
    eq(changes,1)
    n:onLine(own); n:onLine("You are satiated. Your thirst is quenched.")
    eq(n:status().hunger.status,"ravenous"); assert(n:onLine(">"))
    eq(n:status().hunger.status,"satiated"); eq(n:status().thirst.status,"quenched")
    assert(n:onInfo(parser.parseInfo({own,">"})))
    eq(n:status().hunger.status,"ok"); eq(n:status().thirst.status,"ok")
  end
end)

test("foreign wrapped biography and collector-owned lines never leak standalone need updates",function()
  local own="Synthetic Tester"
  local n=Needs.new({epoch=function() return 42 end},nil,function() return own end)
  n:onLine("You are ravenous. You are parched.")
  for _,line in ipairs({"You are Other Tester, a light boned and muscular bodied",
    [[57 year old Entropic Male young Elder. You are 7'7" and weigh 239 lbs. You are]],
    "satiated. Your thirst is", "quenched.","You are hungry. You are thirsty.",">"}) do
    eq(n:onLine(line),false); eq(n:status().hunger.status,"ravenous"); eq(n:status().thirst.status,"parched")
  end
  for _,line in ipairs({"You are Other Tester, a young Elder.",
      "You are satiated. Your thirst is quenched.",">"}) do eq(n:onLine(line,"output",false),false) end
  eq(n:status().hunger.status,"ravenous"); eq(n:status().thirst.status,"parched")
  -- Unowned standalone game notices still belong to the active character.
  assert(n:onLine("You are hungry.")); assert(n:onLine("Your thirst is quenched."))
  eq(n:status().hunger.status,"hungry"); eq(n:status().thirst.status,"quenched")
end)

test("known self rejects identity-less conditions and matching-prefix foreign full names",function()
  local n=Needs.new({epoch=function() return 10 end},nil,function() return {name="Synthetic",full_name="Synthetic Tester"} end)
  n:onLine("You are hungry. You are thirsty.")
  for _,parsed in ipairs({{condition_text=""},
    {character={full_name="Synthetic Other"},condition_text=""},
    {character={full_name="SyntheticTester"},condition_text=""},
    {character={full_name="Synthetic Tester"}}}) do eq(n:onInfo(parsed),false) end
  eq(n:status().hunger.status,"hungry"); eq(n:status().thirst.status,"thirsty")
  -- Retained attributes or biography elsewhere cannot turn a delta into healthy needs.
  eq(n:onInfo({attributes={STR="Good"}}),false)
end)

test("needs character changes and disconnect clear conditions and pending biography",function()
  local identity="Synthetic"
  local n=Needs.new({epoch=function() return 10 end},nil,function() return identity end)
  n:onLine("You are hungry. You are thirsty."); n:onLine("You are Synthetic Tester, a young Elder.")
  identity="Other"; eq(n:status().hunger.status,"unknown"); eq(n:status().thirst.status,"unknown"); eq(n.pending_info,nil)
  eq(n:onLine("You are satiated. Your thirst is quenched."),false); eq(n:onLine(">"),false)
  eq(n:status().hunger.status,"unknown")
  eq(n:onInfo({character={full_name="Synthetic Tester"},condition_text=""}),false)
  n:onLine("You are hungry."); identity=nil
  eq(n:status().hunger.status,"unknown"); eq(n:status().hunger.timestamp,nil)
  eq(n:onInfo({character={full_name="Other Tester"},condition_text=""}),false)
  assert(n:reset()); eq(n:status().thirst.status,"unknown")
end)

test("needs reset preserves quarantine for a pending biography until the prompt",function()
  local n=Needs.new({epoch=function() return 10 end},nil,function() return "Synthetic" end)
  n:onLine("You are Other Tester, a young Elder."); n:reset()
  eq(n:onLine("You are satiated. Your thirst is quenched."),false); eq(n:onLine(">"),false)
  eq(n:status().hunger.status,"unknown"); eq(n:status().thirst.status,"unknown")
  assert(n:onLine("You are hungry.")); eq(n:status().hunger.status,"hungry")
end)

test("needs overflow and stale biographies quarantine healthy continuations",function()
  for _,mode in ipairs({"lines","bytes","stale"}) do
    local stamp=10
    local n=Needs.new({epoch=function() return stamp end},nil,function() return "Synthetic" end)
    n:onLine("You are ravenous. You are parched.")
    n:onLine([[You are Other Tester, a muscular bodied 57 year old Entropic Male young Elder. You are 7'7" and weigh 239 lbs.]])
    if mode=="lines" then for _=1,64 do n:onLine("Harmless INFO detail.") end
    elseif mode=="bytes" then n:onLine(string.rep("x",16385)) else stamp=311 end
    eq(n:onLine("You are satiated. Your thirst is quenched."),false); eq(n:onLine(">"),false)
    eq(n:status().hunger.status,"ravenous"); eq(n:status().thirst.status,"parched")
    assert(n:onLine("You are hungry.")); eq(n:status().hunger.status,"hungry")
  end
end)

local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end

local Parser=require("command_parser")
local biography=[[You are Dace Alterac, a delicate boned and skinny bodied 28 year old Entropic Male young Monitanian. You are 7'0" and weigh 247 lbs.]]
local recoveryNotices={
  {"You're no longer ravenous, only hungry now!","hunger","hungry",{"You're no longer","ravenous, only hungry now!"}},
  {"You're no longer hungry.","hunger","ok",{"You're no longer","hungry."}},
  {"You're full, time to stop eating for a while.","hunger","full",{"You're full, time to stop eating","for a while."}},
  {"You're no longer parched, only thirsty now!","thirst","thirsty",{"You're no longer parched,","only thirsty now!"}},
  {"You're no longer thirsty.","thirst","quenched",{"You're no longer","thirsty."}},
  {"You're sloshing, you've been drinking so much. Time to stop drinking for a while.","thirst","sloshing",
    {"You're sloshing, you've been drinking","so much. Time to stop drinking for a while."}},
}
local function decorateRecoveryNotice(text,variant)
  if variant==2 then return "\7"..text.."\7" end
  if variant==3 then return " \t\27[32m"..text.."\27[0m " end
  if variant==4 then return "> "..text end
  if variant==5 then return "\7\27[33m[199] 147/147 hp, 60/60 ftg > "..text.."\27[0m\7" end
  return text
end

test("exact food and water recovery notices preserve the other need through BEL ANSI and prompts",function()
  for variant=1,5 do for _,notice in ipairs(recoveryNotices) do
    local stamp=10; local changes=0
    local n=Needs.new({epoch=function() return stamp end},function() changes=changes+1 end)
    assert(n:onLine("You are ravenous. You are parched.","info")); local before=n:status()
    stamp=11; assert(n:onLine(decorateRecoveryNotice(notice[1],variant)),notice[1])
    local after=n:status(); local changed=notice[2]; local other=changed=="hunger" and "thirst" or "hunger"
    eq(after[changed].status,notice[3]); eq(after[changed].timestamp,11); eq(after[changed].source,"output")
    assert(after[changed].raw:find(notice[1],1,true)); eq(after[changed].raw:find("\7",1,true),nil)
    eq(after[changed].raw:find("\27",1,true),nil)
    for _,field in ipairs({"status","timestamp","source","raw"}) do eq(after[other][field],before[other][field]) end
    stamp=12
    for _,chatter in ipairs({"You eat the last of your bread.","You drink the last of your water.",
      "You burp","You burp.","Hmmm... not bad","Hmmm... not bad.","Ahh... That hit the spot","Ahh... That hit the spot.",">"}) do
      eq(n:onLine(decorateRecoveryNotice(chatter,variant)),false)
      local unchanged=n:status()
      for _,need in ipairs({"hunger","thirst"}) do
        for _,field in ipairs({"status","timestamp","source","raw"}) do eq(unchanged[need][field],after[need][field]) end
      end
    end
    eq(changes,2)
  end end
end)

test("combined recovery notices update both needs in either sentence order",function()
  for variant=1,5 do for index=1,3 do for _,reverse in ipairs({false,true}) do
    local hunger,thirst=recoveryNotices[index],recoveryNotices[index+3]
    local n=Needs.new({epoch=function() return 42 end}); n:onLine("You are ravenous. You are parched.")
    local text=reverse and thirst[1].." "..hunger[1] or hunger[1].." "..thirst[1]
    assert(n:onLine(decorateRecoveryNotice("You eat some bread. "..text,variant)))
    local state=n:status(); eq(state.hunger.status,hunger[3]); eq(state.thirst.status,thirst[3])
    eq(state.hunger.timestamp,42); eq(state.thirst.timestamp,42)
    eq(state.hunger.source,"output"); eq(state.thirst.source,"output")
  end end end
end)

test("wrapped recovery INFO preserves explicit needs and defaults only the omitted side",function()
  local cases={}
  for _,notice in ipairs(recoveryNotices) do
    cases[#cases+1]={chunks=notice[4],hunger=notice[2]=="hunger" and notice[3] or "ok",
      thirst=notice[2]=="thirst" and notice[3] or "ok"}
  end
  for index=1,3 do
    local chunks={}
    for _,notice in ipairs({recoveryNotices[index],recoveryNotices[index+3]}) do
      for _,chunk in ipairs(notice[4]) do chunks[#chunks+1]=chunk end
    end
    cases[#cases+1]={chunks=chunks,hunger=recoveryNotices[index][3],thirst=recoveryNotices[index+3][3]}
  end
  for _,case in ipairs(cases) do
    local lines={"\27[32m[199] 147/147 hp, 60/60 ftg > "..biography.."\27[0m"}
    for _,chunk in ipairs(case.chunks) do lines[#lines+1]="\7\27[33m"..chunk.."\27[0m\7" end
    lines[#lines+1]=">"
    local parsed=assert(Parser.parseInfo(lines)); eq(parsed.character.full_name,"Dace Alterac")
    for _,observed in ipairs({false,true}) do
      local n=Needs.new({epoch=function() return 42 end}); n:onLine("You are ravenous. You are parched.")
      if observed then for _,line in ipairs(lines) do n:onLine(line) end
      else assert(n:onInfo(parsed)) end
      local state=n:status(); eq(state.hunger.status,case.hunger); eq(state.thirst.status,case.thirst)
      for _,need in ipairs({"hunger","thirst"}) do
        eq(state[need].source,observed and "output" or "info"); eq(state[need].timestamp,42)
      end
    end
  end
end)

test("dehydrated standalone ANSI and wrapped INFO notices retain a water warning",function()
  local n=Needs.new({epoch=function() return 42 end})
  n:onLine("You are hungry.")
  for _,line in ipairs({"You are dehydrated.","\27[31m[199] 147/147 hp, 60/60 ftg >You are dehydrated.\27[0m"}) do
    assert(n:onLine(line)); eq(n:status().thirst.status,"dehydrated"); eq(n:status().hunger.status,"hungry")
  end
  local parsed=assert(Parser.parseInfo({biography,"You are seated. You are dehydrated.",">"}))
  assert(n:onInfo(parsed)); eq(n:status().thirst.status,"dehydrated"); eq(n:status().hunger.status,"ok")
  assert(n:onLine("Your thirst is quenched.")); eq(n:status().thirst.status,"quenched")
end)

test("dehydrated INFO appears as a red warning in the identity box",function()
  local View=require("view"); local theme=require("defaults").theme
  local html=View.identityContent({full_name="Test",race="Human",class="Fighter"},theme,{body_font=14,heading_font=18},{hunger={status="ok"},thirst={status="dehydrated"}})
  assert(html:find("Water:",1,true)); assert(html:find("color:#d34a42'><b>Dehydrated</b>",1,true))
end)

test("quoted room biographies cannot default either need to ok",function()
  local prose=[[You are in a gallery, where a plaque reads "You are Synthetic Tester, a stocky bodied 28 year old Entropic Male young Human. You are 6'0" and weigh 180 lbs."]]
  for _,lines in ipairs({
    {prose,">"},
    {"\27[32m"..prose.."\27[0m",">"},
    {[[You are in a gallery, where a plaque reads "You are Synthetic Tester,]],
      [[a stocky bodied 28 year old Entropic Male young Human. You are 6'0" and weigh 180 lbs."]],">"},
  }) do
    eq(Parser.parseInfo(lines),nil)
    local changes=0
    local n=Needs.new({epoch=function() return 10 end},function() changes=changes+1 end)
    assert(n:onLine("You are ravenous. You are parched."))
    local before=n:status()
    for _,line in ipairs(lines) do n:onLine(line) end
    local after=n:status()
    for _,need in ipairs({"hunger","thirst"}) do
      for _,field in ipairs({"status","timestamp","source","raw"}) do eq(after[need][field],before[need][field]) end
    end
    eq(changes,1)
  end
end)

test("complete INFO overwrites both needs and defaults each missing condition to ok",function()
  for _,case in ipairs({{"","ok","ok"},{" You are hungry.","hungry","ok"},
    {" You are thirsty.","ok","thirsty"},{" You are satiated. Your thirst is quenched.","satiated","quenched"}}) do
    local stamp=10; local n=Needs.new({epoch=function() return stamp end})
    assert(n:onLine("You are ravenous. You are parched.")); stamp=11
    assert(n:onInfo(assert(Parser.parseInfo({biography..case[1],">"}))))
    local s=n:status(); eq(s.hunger.status,case[2]); eq(s.thirst.status,case[3])
    eq(s.hunger.timestamp,11); eq(s.thirst.timestamp,11)
    assert(n:onLine("You are starving.")); eq(n:status().thirst.status,case[3])
    assert(n:onLine("You are very thirsty.")); eq(n:status().hunger.status,"starving")
  end
end)

test("attribute and vitals INFO deltas cannot reset needs even with retained biography elsewhere",function()
  local n=Needs.new({epoch=function() return 10 end}); assert(n:onLine("You are ravenous. You are parched."))
  for _,lines in ipairs({
    {"Str Int Wis Dex Agi Con Cha Wil Pre Per Luk","Good Good Good Good Good Good Good Good Good Good Good",">"},
    {"HP: 213 of 213 Ftg: 81 of 81 Carry: 174.4 of 354.0 lbs.",">"},
    {"You are Dace Alterac, a delicate boned young Monitanian.","HP: 213 of 213",">"},
  }) do
    local parsed=assert(Parser.parseInfo(lines)); eq(parsed.condition_text,nil); eq(n:onInfo(parsed),false)
    eq(n:status().hunger.status,"ravenous"); eq(n:status().thirst.status,"parched")
  end
  eq(n:onInfo(nil),false); eq(n:onInfo({}),false)
end)

test("unsolicited INFO accepts plain wrapped ANSI and prompt-prefixed biographies only at a real prompt",function()
  local cases={
    {lines={biography},prompt=">",hunger="ok",thirst="ok"},
    {lines={"> "..biography.." You are hungry."},prompt=">",hunger="hungry",thirst="ok"},
    {lines={"\27[32m[199] 301/301 hp, 173/173 ftg > "..biography.." You are thirsty.\27[0m"},
      prompt="[199] 301/301 hp, 173/173 ftg >",hunger="ok",thirst="thirsty"},
    {lines={"\27[32m> You are Dace Alterac, a delicate boned and skinny bodied 28 year old Entropic Male young Monitanian.\27[0m",
      [[You are 7'0" and weigh 247 lbs. You are]],"satiated. Your thirst is","quenched."},
      prompt=">",hunger="satiated",thirst="quenched"},
  }
  for _,case in ipairs(cases) do
    local n=Needs.new({epoch=function() return 10 end}); n:onLine("You are ravenous. You are parched.")
    for _,line in ipairs(case.lines) do n:onLine(line) end
    if case.hunger=="ok" then eq(n:status().hunger.status,"ravenous") end
    if case.thirst=="ok" then eq(n:status().thirst.status,"parched") end
    n:onLine(case.prompt); eq(n:status().hunger.status,case.hunger); eq(n:status().thirst.status,case.thirst)
  end
end)

test("startup prompts prose actions and incomplete or malformed biographies never infer ok",function()
  for _,seed in ipairs({false,true}) do
    local n=Needs.new({epoch=function() return 10 end})
    if seed then n:onLine("You are ravenous. You are parched.") end
    for _,line in ipairs({"",">","[199] 301/301 hp, 173/173 ftg >","The room is quiet.",
      "You eat the last of your bread.","You drink the last of your water.",
      "You are Dace Alterac, a delicate boned and skinny bodied 28 year old Entropic Male young Monitanian.",">",
      [[You are Dace Alterac, a young Monitanian. You are tall and weigh many lbs.]],">",biography}) do n:onLine(line) end
    eq(n:status().hunger.status,seed and "ravenous" or "unknown")
    eq(n:status().thirst.status,seed and "parched" or "unknown")
  end
end)

test("unsolicited INFO overflow does not reset needs and a new bounded biography recovers",function()
  for _,overflow in ipairs({"lines","bytes"}) do
    local n=Needs.new({epoch=function() return 10 end}); n:onLine("You are ravenous. You are parched.")
    n:onLine(biography)
    if overflow=="lines" then for _=1,65 do n:onLine("Harmless extra INFO detail.") end
    else n:onLine(string.rep("x",16385)) end
    n:onLine(">"); eq(n:status().hunger.status,"ravenous"); eq(n:status().thirst.status,"parched")
    n:onLine(biography); n:onLine(">"); eq(n:status().hunger.status,"ok"); eq(n:status().thirst.status,"ok")
  end
end)

test("standalone and ANSI healthy notices update only their own need",function()
  for _,ansi in ipairs({false,true}) do
    local stamp=10; local n=Needs.new({epoch=function() return stamp end})
    local function line(value) return ansi and " \t\27[32m"..value.."\27[0m " or value end
    assert(n:onLine("You are hungry. You are parched.","info"))
    stamp=11; assert(n:onLine(line("You are satiated.")))
    local s=n:status(); eq(s.hunger.status,"satiated"); eq(s.hunger.timestamp,11); eq(s.hunger.source,"output")
    eq(s.thirst.status,"parched"); eq(s.thirst.timestamp,10); eq(s.thirst.source,"info")
    stamp=12; assert(n:onLine(line("Your thirst is quenched.")))
    s=n:status(); eq(s.thirst.status,"quenched"); eq(s.thirst.timestamp,12); eq(s.thirst.source,"output")
    eq(s.hunger.status,"satiated"); eq(s.hunger.timestamp,11)
  end
end)

test("healthy needs can worsen and recover independently",function()
  local n=Needs.new({epoch=function() return 42 end})
  for _,step in ipairs({
    {"You are satiated. Your thirst is quenched.","satiated","quenched"},
    {"You are hungry.","hungry","quenched"},
    {"You are very thirsty.","hungry","very_thirsty"},
    {"You are satiated.","satiated","very_thirsty"},
    {"Your thirst is quenched.","satiated","quenched"},
    {"You are ravenous.","ravenous","quenched"},
    {"You are parched.","ravenous","parched"},
    {"You are starving.","starving","parched"},
  }) do assert(n:onLine(step[1])); local s=n:status(); eq(s.hunger.status,step[2]); eq(s.thirst.status,step[3]) end
end)

test("actions and bare quenched prose do not infer healthy needs",function()
  local changes=0; local n=Needs.new({epoch=function() return 7 end},function() changes=changes+1 end)
  assert(n:onLine("You are hungry. You are very thirsty.","info"))
  local before=n:status()
  for _,line in ipairs({"You eat the last of your bread.","You drink the last of your water.",
    "Quenched.","The fire is quenched.","Your thirst is quenched","Your thirst is not quenched."}) do
    eq(n:onLine(line),false)
    local s=n:status()
    for _,need in ipairs({"hunger","thirst"}) do
      for _,field in ipairs({"status","timestamp","source","raw"}) do eq(s[need][field],before[need][field]) end
    end
  end
  eq(changes,1)
end)

test("confirmed hunger and thirst phrases update independent states",function()
  local n=Needs.new({epoch=function() return 42 end})
  for phrase,want in pairs({["You are starting to feel hungry."]="hungry",["You are hungry."]="hungry",["You are ravenous."]="ravenous",["You are ravenously hungry."]="ravenous",["You are starving."]="starving",["You feel like you're starving, you're so hungry."]="starving",["You are satiated."]="satiated"}) do n:onLine(phrase); eq(n:status().hunger.status,want) end
  for phrase,want in pairs({["You are starting to feel thirsty."]="thirsty",["You are thirsty."]="thirsty",["You are very thirsty."]="very_thirsty",["You are parched."]="parched"}) do n:onLine(phrase); eq(n:status().thirst.status,want) end
end)
test("combined INFO ANSI and action lines remain conservative",function()
  local n=Needs.new({epoch=function() return 7 end}); n:onLine("\27[31mYou are hidden. You are hungry. You are very thirsty.\27[0m","info")
  local s=n:status(); eq(s.hunger.status,"hungry"); eq(s.thirst.status,"very_thirsty"); eq(s.thirst.timestamp,7); eq(s.thirst.source,"info")
  eq(n:onLine("You eat the last of your bread."),false); eq(n:onLine("You drink the last of your water."),false); eq(n:status().hunger.status,"hungry"); eq(n:status().thirst.status,"very_thirsty")
end)
