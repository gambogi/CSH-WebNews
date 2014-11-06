require 'rails_helper'

RSpec.describe 'Sticky update' do
  it 'changes the sticky expiration time for a post' do
    post = create(:post)
    date = 13.days.from_now
    allow_any_instance_of(User).to receive(:admin?).and_return(true)

    patch post_sticky_path(post), expires_at: date

    expect(response.status).to be 204
    get post_path(post)
    expect(response_json[:post][:sticky]).to eq({
      username: oauth_user.username,
      display_name: oauth_user.real_name,
      expires_at: date.iso8601
    })
  end

  it 'returns error information when given an invalid request' do
    patch post_sticky_path(create(:post)), expires_at: 2.days.ago

    expect(response.status).to be 422
    expect(response_json).to eq({
      errors: {
        expires_at: ['must be in the future'],
        post: ['requires admin privileges to sticky']
      }
    })
  end
end