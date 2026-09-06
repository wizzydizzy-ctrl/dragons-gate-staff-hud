local Catalog={}
local fields={slug=true,name=true,author=true,publisher=true,description=true,version=true,areas=true,room_count=true,bytes=true,download_url=true,sha256=true}
local function fail(message) return nil,"invalid map catalog: "..message end
local function integer(value) return type(value)=="number" and value==math.floor(value) end
local function plain(value,limit,empty) return type(value)=="string" and #value<=limit and (empty or #value>0) and not value:find("[%z\1-\31\127]") end
local function dense(value,limit) if type(value)~="table" then return nil end; local count=0; for key in pairs(value) do if not integer(key) or key<1 or key>limit then return nil end; count=count+1 end; for i=1,count do if value[i]==nil then return nil end end; return count end
local function validateEntry(entry,index)
  if type(entry)~="table" then return fail("maps["..index.."] must be an object") end; for key in pairs(entry) do if not fields[key] then return fail("maps["..index.."] has unknown field "..key) end end; for key in pairs(fields) do if entry[key]==nil then return fail("maps["..index.."] is missing "..key) end end
  if not plain(entry.slug,64) or not entry.slug:match("^[a-z0-9][a-z0-9_%-]*$") then return fail("maps["..index.."].slug is invalid") end
  if not plain(entry.name,100) or not plain(entry.author,80) or not plain(entry.publisher,39) or not entry.publisher:match("^[A-Za-z0-9][A-Za-z0-9%-]*$") then return fail("maps["..index.."] identity is invalid") end
  if not plain(entry.description,500,true) or not plain(entry.version,32) or not entry.version:match("^%d+%.%d+%.%d+") then return fail("maps["..index.."] metadata is invalid") end
  local areaCount=dense(entry.areas,100); if not areaCount or areaCount<1 then return fail("maps["..index.."].areas is invalid") end; local areas,seen={},{}; for i,area in ipairs(entry.areas) do if not plain(area,100) or seen[area] then return fail("maps["..index.."].areas is invalid") end; seen[area]=true; areas[i]=area end
  if not integer(entry.room_count) or entry.room_count<1 or entry.room_count>100000 or not integer(entry.bytes) or entry.bytes<1 or entry.bytes>20000000 then return fail("maps["..index.."] size is invalid") end
  if type(entry.sha256)~="string" or not entry.sha256:match("^[0-9a-f]+$") or #entry.sha256~=64 then return fail("maps["..index.."].sha256 is invalid") end
  local prefix="https://raw.githubusercontent.com/wizzydizzy%-ctrl/dragons%-gate%-map%-library/"; local ref,path=tostring(entry.download_url):match("^"..prefix.."([A-Za-z0-9][A-Za-z0-9._%-]*)/(maps/.+)$"); if not ref or path~="maps/"..entry.publisher.."/"..entry.slug..".json" then return fail("maps["..index.."].download_url is not approved") end
  return {slug=entry.slug,name=entry.name,author=entry.author,publisher=entry.publisher,description=entry.description,version=entry.version,areas=areas,room_count=entry.room_count,bytes=entry.bytes,download_url=entry.download_url,sha256=entry.sha256}
end
function Catalog.validate(value)
  if type(value)~="table" or value.schema~=1 then return fail("schema must equal 1") end; for key in pairs(value) do if key~="schema" and key~="maps" then return fail("root has unknown field") end end; local count=dense(value.maps,1000); if not count then return fail("maps must be a dense array") end
  local result={schema=1,maps={}}; local seen={}; for i=1,count do local entry,err=validateEntry(value.maps[i],i); if not entry then return nil,err end; local id=entry.publisher:lower().."/"..entry.slug; if seen[id] then return fail("maps contains duplicate "..id) end; seen[id]=true; result.maps[i]=entry end; return result
end
function Catalog.select(value,publisher,slug) local catalog,err=Catalog.validate(value); if not catalog then return nil,err end; for _,entry in ipairs(catalog.maps) do if entry.publisher:lower()==tostring(publisher):lower() and entry.slug==slug then return entry end end; return nil,"map not found" end
return Catalog
