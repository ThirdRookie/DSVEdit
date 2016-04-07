
require_relative 'ui_text_editor'

class TextEditor < Qt::Dialog
  slots "string_changed(int)"
  slots "save_button_pressed()"
  slots "button_pressed(QAbstractButton*)"
  
  def initialize(main_window, fs)
    super(main_window)
    @ui = Ui_TextEditor.new
    @ui.setup_ui(self)
    
    @fs = fs
    
    @text_database = TextDatabase.new(fs)
    
    @text_database.text_list.each do |text|
      string = text.decoded_string
      if string.include?("\n")
        newline_index = string.index("\n")
        string = string[0, newline_index]
      end
      if string.length > 18
        string = string[0,18]
      end
      string += "..." unless string == text.decoded_string
      @ui.text_list.addItem("%03X %08X %s" % [text.text_id, text.string_ram_pointer, string])
    end
    
    connect(@ui.text_list, SIGNAL("currentRowChanged(int)"), self, SLOT("string_changed(int)"))
    connect(@ui.buttonBox, SIGNAL("clicked(QAbstractButton*)"), self, SLOT("button_pressed(QAbstractButton*)"))
    
    #self.setWindowFlags(Qt::MSWindowsFixedSizeDialogHint);
    
    self.show()
  end
  
  def string_changed(text_id)
    text = @text_database.text_list[text_id]
    
    @ui.textEdit.setPlainText(text.decoded_string)
  end
  
  def button_pressed(button)
    if @ui.buttonBox.standardButton(button) == Qt::DialogButtonBox::Apply
      save_current_text()
    end
  end
  
  def save_current_text
    text = @text_database.text_list[@ui.text_list.currentRow]
    
    text.decoded_string = @ui.textEdit.toPlainText()
    
    @text_database.write_to_rom()
  end
end
