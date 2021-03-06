class Subscription < ActiveRecord::Base
  DIGEST_TYPES = %w(none daily weekly monthly)

  belongs_to :user
  belongs_to :newsgroup, foreign_key: :newsgroup_name, primary_key: :name

  validates :user, presence: true
  validates :newsgroup_name, uniqueness: { scope: :user_id, message: 'is duplicated' }
  validates :unread_level, :email_level, numericality: {
    greater_than_or_equal_to: 0, less_than: PERSONAL_CODES.length, allow_nil: true
  }
  validates :digest_type, inclusion: { in: DIGEST_TYPES, allow_blank: true }

  def self.for(newsgroup)
    find_by_newsgroup_name(newsgroup.name)
  end

  def self.send_digests!
    old_zone = Time.zone

    User.find_each do |user|
      Time.zone = user.time_zone
      now = Time.now

      if now.between?(now.beginning_of_day + 30.minutes, now.beginning_of_day + 90.minutes)
        Mailer.posts_digest(
          user,
          now.beginning_of_day - 1.day,
          now.end_of_day - 1.day,
          'daily_digest'
        ).deliver
      end

      if now.between?(now.beginning_of_week + 30.minutes, now.beginning_of_week + 90.minutes)
        Mailer.posts_digest(
          user,
          now.beginning_of_week - 1.week,
          now.end_of_week - 1.week,
          'weekly_digest'
        ).deliver
      end

      if now.between?(now.beginning_of_month + 30.minutes, now.beginning_of_month + 90.minutes)
        Mailer.posts_digest(
          user,
          now.beginning_of_month - 1.month,
          now.end_of_month - 1.month,
          'monthly_digest'
        ).deliver
      end
    end

    Time.zone = old_zone
  end
end
