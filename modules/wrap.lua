-- ************************************************************************
--
--    Text wrapping experiment.
--    Copyright 2019 by Sean Conner.  All Rights Reserved.
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
--    Comments, questions and criticisms can be sent to: sean@conman.org
--
-- ************************************************************************
-- luacheck: globals handler
-- luacheck: ignore 611 631
-- RFC-3875

local wrapt    = require "org.conman.string".wrapt
local table    = require "table"
local tonumber = tonumber
local ipairs   = ipairs

_ENV = {}

local text =
{
  [[Lorem ipsum dolor sit amet, consectetur adipiscing elit. Cras sodales eget nisi quis condimentum. Donec ipsum arcu, fermentum eu ullamcorper sit amet, facilisis id nunc. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Nam tempus nulla ut dolor luctus malesuada. Suspendisse orci sem, semper at maximus non, pharetra et justo. Quisque lectus arcu, viverra ac convallis eu, vulputate ut enim. Nulla aliquam, lacus consequat suscipit facilisis, nisl tortor facilisis nisi, vel mattis eros arcu sed tellus. Duis quis lectus pellentesque, posuere dolor ut, sodales massa. Proin vel blandit mauris.]],
  [[Aenean vehicula eu eros vel feugiat. Quisque sagittis metus eu nisl dapibus condimentum. Aenean ipsum justo, sagittis vel ipsum sit amet, fermentum convallis elit. Ut congue scelerisque velit, nec euismod nulla gravida quis. Duis faucibus tempus ligula, non malesuada neque lobortis quis. Nam neque magna, ornare eu dui ut, porttitor tincidunt purus. Duis id malesuada ante. Suspendisse gravida condimentum nisl, eget gravida dui pellentesque et.]],
  [[Fusce tempor leo nulla, non posuere sem maximus eget. Integer non maximus quam. Nam ac felis ut elit aliquam aliquam. Curabitur laoreet metus nulla, a ornare lorem molestie a. Sed id libero vel nunc lobortis lacinia sed quis metus. Sed feugiat eget ipsum et commodo. Fusce condimentum est ut arcu imperdiet, vel porta felis tincidunt. Aliquam quis molestie libero, sit amet luctus quam. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Suspendisse potenti. Integer quis eros neque. Sed vulputate condimentum est et cursus. Nunc urna ante, euismod quis tempus ac, aliquam at felis. Sed hendrerit ex eu odio sodales fermentum.]],
  [[Fusce faucibus dui et consectetur aliquet. Nullam augue magna, bibendum sit amet commodo at, sagittis non leo. Sed eget mauris eget arcu vulputate vulputate. Morbi non gravida dolor, in mollis turpis. Ut quis tempor elit. Aenean nec arcu vitae justo gravida placerat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nam vel suscipit nisi. Curabitur vitae elit ultricies, ultrices dolor sed, vehicula augue. Phasellus euismod ligula sit amet mi volutpat tempor. Nunc scelerisque mauris dui, sed placerat nibh tempus non. Mauris eleifend purus nec tincidunt dapibus. Maecenas tincidunt volutpat varius. Phasellus eu congue risus. Nam venenatis erat non auctor ullamcorper.]],
  [[Nunc pharetra sem nec velit tempus, sed malesuada felis accumsan. Vestibulum egestas ex nisl, sit amet rhoncus mauris laoreet at. Ut neque lorem, tempus et dictum non, laoreet ac mauris. Maecenas consectetur blandit neque eget maximus. Duis tincidunt elementum lorem, at varius nisl dapibus vel. In blandit ipsum sed molestie commodo. Quisque aliquet nunc eget pretium viverra. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Morbi ligula nisi, sollicitudin tincidunt efficitur nec, lobortis eu diam. Vestibulum convallis erat velit, semper semper augue sodales in.]],
}

function handler(_,_,_,match)
  local width = tonumber(match[1]) or 77
  local res   = {}
  
  if width < 1 then width = 1 end
  
  for _,line in ipairs(text) do
    local paragraph = wrapt(line,width)
    for _,segment in ipairs(paragraph) do
      table.insert(res,segment)
    end
    table.insert(res,"")
  end
  
  return 20,"text/plain",table.concat(res,"\r\n") .. "\r\n"
end

return _ENV
