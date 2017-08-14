
require 'nokogiri'

class DarkFunctionInterface
  def self.export(output_path, name, sprite_info, fs, renderer)
    sprite = sprite_info.sprite
    
    palettes = renderer.generate_palettes(sprite_info.palette_pointer, 16)
    
    num_gfx_pages = sprite_info.gfx_pages.size
    num_gfx_palette_combos = num_gfx_pages*palettes.size
    gfx_page_canvas_width = sprite_info.gfx_pages.first.canvas_width*8
    gfx_page_width = gfx_page_canvas_width
    
    big_gfx_page_width = Math.sqrt(num_gfx_palette_combos).ceil
    big_gfx_page_height = (num_gfx_palette_combos / big_gfx_page_width.to_f).ceil
    
    # Make sure the big gfx page is at least 256 pixels wide for the hitboxes.
    if gfx_page_width == 128
      big_gfx_page_width = [big_gfx_page_width, 2].max
    end
    # Add an extra 256 pixels to the height for the hitboxes.
    if gfx_page_width == 128
      big_gfx_page_height += 2
    else
      big_gfx_page_height += 1
    end
    
    big_gfx_page = ChunkyPNG::Image.new(big_gfx_page_width*gfx_page_width, big_gfx_page_height*gfx_page_width)
    palettes.each_with_index do |palette, palette_index|
      sprite_info.gfx_pages.each_with_index do |gfx_page, gfx_page_index|
        chunky_gfx_page = renderer.render_gfx_page(gfx_page.file, palette, gfx_page.canvas_width)
        
        i = gfx_page_index + (palette_index*num_gfx_pages)
        x_on_big_gfx_page = (i % big_gfx_page_width) * gfx_page_width
        y_on_big_gfx_page = (i / big_gfx_page_width) * gfx_page_width
        big_gfx_page.compose!(chunky_gfx_page, x_on_big_gfx_page, y_on_big_gfx_page)
      end
    end
    hitbox_red_rect = ChunkyPNG::Image.new(big_gfx_page_width*gfx_page_width, 256, ChunkyPNG::Color.rgba(0xFF, 0, 0, 0x3f))
    hitbox_red_x_off = 0
    hitbox_red_y_off = big_gfx_page.height-hitbox_red_rect.height
    big_gfx_page.compose!(hitbox_red_rect, hitbox_red_x_off, hitbox_red_y_off)
    big_gfx_page.save(output_path + "/#{name}.png")
    
    unique_parts_by_index = sprite.get_unique_parts_by_index()
    unique_parts = unique_parts_by_index.values.map{|dup_data| dup_data[:unique_part]}.uniq
    
    unique_hitboxes_by_index = sprite.get_unique_hitboxes_by_index()
    unique_hitboxes = unique_hitboxes_by_index.values.map{|dup_data| dup_data[:unique_hitbox]}.uniq
    
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.img(:name => "#{name}.png", 
              :w => gfx_page_width, 
              :h => gfx_page_width) {
        xml.definitions {
          xml.dir(:name => "/") {
            unique_parts.each_with_index do |part, i|
              part_index = sprite.parts.index(part)
              gfx_page_index = part.gfx_page_index
              if gfx_page_canvas_width == 256
                # 256x256 pages take up 4 times the space of 128x128 pages.
                gfx_page_index = gfx_page_index / 4
              end
              i_on_big_gfx_page = gfx_page_index + (part.palette_index*num_gfx_pages)
              big_gfx_x_offset = (i_on_big_gfx_page % big_gfx_page_width) * gfx_page_width
              big_gfx_y_offset = (i_on_big_gfx_page / big_gfx_page_width) * gfx_page_width
              xml.spr(:name => "%02X" % part_index,
                      :x => part.gfx_x_offset + big_gfx_x_offset,
                      :y => part.gfx_y_offset + big_gfx_y_offset,
                      :w => part.width,
                      :h => part.height
              )
            end
            
            unique_hitboxes.each_with_index do |hitbox, i|
              hitbox_index = sprite.hitboxes.index(hitbox)
              xml.spr(:name => "hitbox%02X" % hitbox_index,
                      :x => hitbox_red_x_off,
                      :y => hitbox_red_y_off,
                      :w => hitbox.width,
                      :h => hitbox.height
              )
            end
          }
        }
      }
    end
    
    filename = output_path + "/#{name}.sprites"
    FileUtils::mkdir_p(File.dirname(filename))
    File.open(filename, "w") do |f|
      f.write(builder.to_xml)
    end
    
    # We need to preserve unanimated frames by creating dummy animations containing them.
    # This also doubles as preserving the proper order of animated frames.
    animations_plus_unanimated_frames = []
    max_seen_frame_index = -1
    num_unanimated_frames = 0
    sprite.animations.each_with_index do |animation, animation_index|
      unanimated_frame_indexes_to_insert = []
      
      animation.frame_delays.each do |frame_delay|
        if frame_delay.frame_index <= max_seen_frame_index
          # Do nothing. This is just a duplicated frame.
        elsif frame_delay.frame_index == max_seen_frame_index + 1
          # This is the next sequential frame.
          max_seen_frame_index = frame_delay.frame_index
        else
          # It skipped a frame (or multiple frames). We must insert these as unanimated frames before this next animation so that it's correctly preserved.
          unanimated_frame_indexes_to_insert += (max_seen_frame_index+1..frame_delay.frame_index-1).to_a
          max_seen_frame_index = frame_delay.frame_index-1
        end
      end
      
      unanimated_frame_indexes_to_insert.each do |unanimated_frame_index|
        dummy_frame_delay = FrameDelay.new
        dummy_frame_delay.frame_index = unanimated_frame_index
        
        animations_plus_unanimated_frames << {name: "unanimated frame %02X" % num_unanimated_frames, frame_delays: [dummy_frame_delay]}
        num_unanimated_frames += 1
      end
      
      animations_plus_unanimated_frames << {name: "%02X" % animation_index, frame_delays: animation.frame_delays}
    end
    
    if max_seen_frame_index < sprite.frames.size-1
      (max_seen_frame_index+1..sprite.frames.size-1).each do |unanimated_frame_index|
        dummy_frame_delay = FrameDelay.new
        dummy_frame_delay.frame_index = unanimated_frame_index
        
        animations_plus_unanimated_frames << {name: "unanimated frame %02X" % num_unanimated_frames, frame_delays: [dummy_frame_delay]}
        num_unanimated_frames += 1
      end
    end
    
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.animations(:spriteSheet => "#{name}.sprites", 
                     :ver => "1.2") {
        animations_plus_unanimated_frames.each do |hash|
          xml.anim(:name => hash[:name], :loops => 0) {
            hash[:frame_delays].each_with_index do |frame_delay, i|
              xml.cell(:index => "%02X" % i,
                       :delay => frame_delay.delay/2 # darkFunction runs at 30fps, the game engine runs at 60fps.
              ) {
                frame = sprite.frames[frame_delay.frame_index]
                part_z_index = 0
                frame.part_indexes.each do |part_index|
                  # darkFunction places parts so that their center is at the position given.
                  # But the game engine places it so that the part's upper left corner is at the position given.
                  # So we need to add half the part's width and height so it matches up.
                  dup_data = unique_parts_by_index[part_index]
                  part = dup_data[:unique_part]
                  x = dup_data[:x_pos]
                  y = dup_data[:y_pos]
                  horizontal_flip = dup_data[:horizontal_flip]
                  vertical_flip = dup_data[:vertical_flip]
                  unique_part_index = sprite.parts.index(part)
                  xml.spr(:name => "/%02X" % unique_part_index,
                          :x => x + part.width/2,
                          :y => y + part.height/2,
                          :z => part_z_index,
                          :flipH => horizontal_flip ? 1 : 0,
                          :flipV => vertical_flip ? 1 : 0
                  )
                  part_z_index += 1
                end
                
                frame.hitbox_indexes.each do |hitbox_index|
                  dup_data = unique_hitboxes_by_index[hitbox_index]
                  hitbox = dup_data[:unique_hitbox]
                  x = dup_data[:x_pos]
                  y = dup_data[:y_pos]
                  unique_hitbox_index = sprite.hitboxes.index(hitbox)
                  xml.spr(:name => "/hitbox%02X" % unique_hitbox_index,
                          :x => x + hitbox.width/2,
                          :y => y + hitbox.height/2,
                          :z => 999 # We want hitboxes to appear below the graphics.
                  )
                end
              }
            end
          }
        end
      }
    end
    
    filename = output_path + "/#{name}.anim"
    FileUtils::mkdir_p(File.dirname(filename))
    File.open(filename, "w") do |f|
      f.write(builder.to_xml)
    end
  end
  
  def self.import(input_path, name, sprite_info, fs, renderer)
    sprite = sprite_info.sprite
    
    gfx_page_canvas_width = sprite_info.gfx_pages.first.canvas_width*8
    gfx_page_width = gfx_page_canvas_width
    num_gfx_pages = sprite_info.gfx_pages.size
    palettes = renderer.generate_palettes(sprite_info.palette_pointer, 16)
    num_palettes = palettes.size
    num_gfx_palette_combos = num_gfx_pages*palettes.size
    big_gfx_page_width = Math.sqrt(num_gfx_palette_combos).ceil
    
    sprites_file = File.read(input_path + "/#{name}.sprites")
    anim_file = File.read(input_path + "/#{name}.anim")
    
    xml = Nokogiri::XML(sprites_file)
    df_unique_parts = {}
    xml.css("spr").each do |df_spr|
      df_unique_parts["/" + df_spr["name"]] = df_spr
    end
    
    # Empty the arrays so we can create them from scratch.
    sprite.frames.clear()
    sprite.parts.clear()
    sprite.hitboxes.clear()
    sprite.animations.clear()
    sprite.frame_delays.clear()
    
    each_frames_unique_part_names = {}
    
    xml = Nokogiri::XML(anim_file)
    df_anims = xml.css("anim")
    df_anims.each do |df_anim|
      unless df_anim[:name].start_with?("unanimated")
        animation = Animation.new
        animation.first_frame_delay_offset = sprite.frame_delays.size*FrameDelay.data_size
        sprite.animations << animation
      end
      
      df_cells = df_anim.css("cell")
      df_cells.each do |df_cell|
        frame_delay = FrameDelay.new
        frame_delay.delay = df_cell["delay"].to_i * 2 # darkFunction runs at 30fps, the game engine runs at 60fps.
        sprite.frame_delays << frame_delay
        animation.number_of_frames += 1 unless df_anim[:name].start_with?("unanimated")
        
        frame_index = sprite.frames.size
        frame = Frame.new
        frame.first_part_offset = sprite.parts.size*Part.data_size
        frame.first_hitbox_offset = sprite.hitboxes.size*Hitbox.data_size
        
        this_frames_unique_part_names = []
        this_frames_parts = []
        this_frames_hitboxes = []
        
        df_sprs = df_cell.css("spr")
        df_sprs_z_sorted = df_sprs.sort_by{|df_spr| df_spr["z"].to_i}
        df_sprs_z_sorted.each do |df_spr|
          if df_spr["name"].start_with?("/hitbox")
            hitbox = Hitbox.new
            frame.number_of_hitboxes += 1
            
            this_frames_unique_part_names << df_spr["name"]
            df_unique_hitbox = df_unique_parts[df_spr["name"]]
            hitbox.width = df_unique_hitbox["w"].to_i
            hitbox.height = df_unique_hitbox["h"].to_i
            
            hitbox.x_pos = df_spr["x"].to_i - hitbox.width/2
            hitbox.y_pos = df_spr["y"].to_i - hitbox.height/2
            
            this_frames_hitboxes << hitbox
          else
            part = Part.new
            frame.number_of_parts += 1
            
            this_frames_unique_part_names << df_spr["name"]
            df_unique_part = df_unique_parts[df_spr["name"]]
            x_on_big_gfx_page = df_unique_part["x"].to_i
            y_on_big_gfx_page = df_unique_part["y"].to_i
            part.gfx_x_offset = x_on_big_gfx_page % gfx_page_width
            part.gfx_y_offset = y_on_big_gfx_page % gfx_page_width
            part.width = df_unique_part["w"].to_i
            part.height = df_unique_part["h"].to_i
            gfx_page_index_on_big_gfx_page = (x_on_big_gfx_page / gfx_page_width) + (y_on_big_gfx_page / gfx_page_width * big_gfx_page_width)
            gfx_page_index = gfx_page_index_on_big_gfx_page % num_gfx_pages
            if gfx_page_canvas_width == 256
              # 256x256 pages take up 4 times the space of 128x128 pages.
              gfx_page_index = gfx_page_index * 4
            end
            part.gfx_page_index = gfx_page_index
            part.palette_index = gfx_page_index_on_big_gfx_page / num_gfx_pages
            
            part.x_pos = df_spr["x"].to_i - part.width/2
            part.y_pos = df_spr["y"].to_i - part.height/2
            part.horizontal_flip = (df_spr["flipH"].to_i == 1)
            part.vertical_flip = (df_spr["flipV"].to_i == 1)
            
            this_frames_parts << part
          end
        end
        
        duplicated_frame_and_part_names = each_frames_unique_part_names.find do |frame_index, other_frames_unique_part_names|
          this_frames_unique_part_names == other_frames_unique_part_names
        end
        if duplicated_frame_and_part_names
          duplicated_frame_index = duplicated_frame_and_part_names[0]
          frame_delay.frame_index = duplicated_frame_index
        else
          frame_delay.frame_index = frame_index
          sprite.frames << frame
          each_frames_unique_part_names[frame_index] = this_frames_unique_part_names
          sprite.parts.concat(this_frames_parts)
          sprite.hitboxes.concat(this_frames_hitboxes)
        end
      end
    end
    
    sprite.write_to_rom()
  end
end
