class ColumnHeader < QuestionnaireHeader
  def complete(_count, _answer = nil)
    html = '<tr>'
    html += '<th style="width: 15%">' + self.txt + '</th>'
    html.html_safe
  end

  def view_answered_question(_count, _answer)
    html = '<tr>'
    html += '<th style="width: 15%">' + self.txt + '</th>'
    html.html_safe
  end
end
