local Catalog=require("map_catalog")
local function entry() return {slug="spur",name="Spur",author="Gia",publisher="gia",description="City",version="1.0.0",areas={"Spur"},room_count=10,bytes=100,download_url="https://raw.githubusercontent.com/wizzydizzy-ctrl/dragons-gate-map-library/main/maps/gia/spur.json",sha256=string.rep("a",64)} end
test("validates secure map catalog entries",function() local result=assert(Catalog.validate({schema=1,maps={entry()}})); eq(result.maps[1].slug,"spur") end)
test("accepts an empty map catalog",function() eq(#assert(Catalog.validate({schema=1,maps={}})).maps,0) end)
test("rejects foreign URLs and malformed checksums",function() local item=entry(); item.download_url="https://example.com/map.json"; eq(Catalog.validate({schema=1,maps={item}}),nil); item=entry(); item.sha256="bad"; eq(Catalog.validate({schema=1,maps={item}}),nil) end)
