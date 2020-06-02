class SectionHeader < QuestionnaireHeader
  def complete(_count, _answer = nil)
    html = '<b style="color: #986633; font-size: x-large">' + self.txt + '</b><br/><br/>'
    html.html_safe
  end

  def view_answered_question(_count, _answer)
    html = '<b style="color: #986633; font-size: x-large">' + self.txt + '</b>'
    html.html_safe
  end
end
