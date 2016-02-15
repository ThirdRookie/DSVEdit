class Sector
  class SectorReadError < StandardError ; end
  
  attr_reader :fs,
              :area,
              :sector_ram_pointer,
              :sector_index,
              :rooms

  def initialize(area, sector_index, sector_ram_pointer, fs)
    @area = area
    @sector_ram_pointer = sector_ram_pointer
    @sector_index = sector_index
    @fs = fs
    read_from_rom()
  end
  
  def read_from_rom
    load_necessary_overlay()
    
    @rooms = []
    room_index = 0
    while true
      #puts "#{area.area_index}-#{sector_index}-#{room_index}"
      room_metadata_ram_pointer = fs.read(sector_ram_pointer + room_index*4, 4).unpack("V*").first
      
      break if room_metadata_ram_pointer == 0
      if INVALID_ROOMS.include?(room_metadata_ram_pointer)
        room_index += 1
        next # unused, mispointed rooms
      end
      
      room = Room.new(room_metadata_ram_pointer, area.area_index, sector_index, room_index, fs)
      @rooms << room
      
      room_index += 1
    end
  end
  
  def load_necessary_overlay
    overlay_id = AREA_INDEX_TO_OVERLAY_INDEX[area.area_index][sector_index]
    fs.load_overlay(overlay_id)
  end
end
