require 'rails_helper'

RSpec.describe 'Post index' do
  it 'retrieves info about posts matching given criteria' do
    target_posts = [
      create(:post, unread_for: oauth_user, created_at: 20.hours.ago),
      create(:post, unread_for: oauth_user, created_at: 30.hours.ago)
    ]
    other_posts = [
      create(:post, unread_for: oauth_user, created_at: 40.hours.ago),
      create(:post, created_at: 10.hours.ago),
      create(:post, unread_for: oauth_user, created_at: 4.days.ago),
      create(:post, created_at: 5.days.ago)
    ]

    get posts_path(only_unread: true, since: 3.days.ago, limit: 2)

    expect(response).to be_successful
    expect(response_json.keys).to match_array [:posts, :meta]
    expect(response_json[:posts].map{ |post| post[:id] }).to eq target_posts.map(&:id)
    expect(response_json[:meta]).to eq({
      results: 2, total: 3, matched_ids: target_posts.map(&:id)
    })
  end

  it 'retrieves info about threads containing posts matching given criteria' do
    target_newsgroup = create(:newsgroup)
    target_roots = create_list(:post, 2, newsgroups: [target_newsgroup])
    first_root_reply = create(:post, parent: target_roots.first)
    target_posts = [
      create(:post, parent: first_root_reply, body: 'sweet googly foogly', created_at: 1.day.ago),
      create(:post, parent: target_roots.last, body: 'much googly toogly', created_at: 2.days.ago),
      create(:post, parent: target_roots.first, body: 'very doogly googly', created_at: 3.days.ago)
    ]
    create(:post, newsgroups: [target_newsgroup], body: 'such googly moogly')
    last_root_reply = create(:post, parent: target_roots.last, body: 'many moogly googly')
    other_root = create(:post)
    create(:post, parent: other_root, body: 'great googly boogly')

    get posts_path(
      newsgroup_ids: target_newsgroup.id,
      keywords: 'googly -moogly',
      as_threads: true
    )

    expect(response).to be_successful
    expect(response_json.keys).to match_array [:posts, :meta, :descendants]
    expect(response_json[:posts].map{ |post| post[:id] }).to eq target_roots.map(&:id)
    expect(response_json[:descendants].map{ |post| post[:id] }).to match_array(
      target_posts.map(&:id) + [first_root_reply.id, last_root_reply.id]
    )
    expect(response_json[:meta]).to eq({
      results: 3, total: 3, matched_ids: target_posts.map(&:id)
    })
  end

  it 'returns error information when given invalid parameters' do
    get posts_path(limit: 0)

    expect(response.status).to be 422
    expect(response_json).to eq({
      errors: { limit: ['must be greater than or equal to 1'] }
    })
  end

  it 'can retrieve only the meta information for the query' do
    target_posts = create_list(:post, 3, unread_for: oauth_user)
    create_list(:post, 2)

    get posts_path(limit: 1, only_unread: true, as_meta: true)

    expect(response_json.keys).to eq [:meta]
    expect(response_json[:meta]).to eq({
      results: 1, total: 3, matched_ids: [target_posts.last.id]
    })
  end
end