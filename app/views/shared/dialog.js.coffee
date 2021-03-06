open_dialog('<%= j render(controller.action_name) %>')
switch '<%= j raw(controller.controller_name + '/' + controller.action_name) %>'
  when 'posts/search_entry'
    $('input[name="keywords"]').focus()
  when 'posts/new'
    if $('#post_body').val() != ''
      $('#post_body').focusAtEnd()
    else
      $('#overlay').focus()
    set_draft_interval()
  when 'posts/edit_sticky'
    if $('#sticky_until').val() == ''
      $('#sticky_until').focus()
  else
    $('#overlay').focus()
