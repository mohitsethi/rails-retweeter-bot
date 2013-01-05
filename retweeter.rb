class Retweeter
  # below this retweet count we don't even check favorites count to save API calls
  MIN_RETWEET_COUNT = 5
  THREE_MONTHS = 90 * 86400

  def initialize(twitter)
    @twitter = twitter
  end

  def retweet_new_tweets
    tweets = load_home_timeline
    matching = tweets.select { |t| interesting_tweet?(t) && !t.retweeted }
    matching.each { |t| retweet(t) }
  end

  def last_three_months_json(extra_users = nil)
    users = followed_users
    users |= extra_users if extra_users

    tweets_json = users.map { |u| load_user_timeline(u).map(&:attrs) }

    Hash[users.zip(tweets_json)]
  end

  def followed_users
    @twitter.following.map(&:screen_name).sort
  end

  def load_home_timeline
    with_activity_data(load_timeline(:home_timeline))
  end

  def load_user_timeline(login)
    three_months_ago = Time.now - THREE_MONTHS

    $stderr.print "@#{login} ."
    tweets = load_timeline(:user_timeline, login)

    while tweets.last.created_at > three_months_ago
      $stderr.print '.'
      batch = load_timeline(:user_timeline, login, :max_id => tweets.last.id - 1)
      break if batch.empty?
      tweets.concat(batch)
    end

    $stderr.print '*'
    tweets = with_activity_data(tweets.reject { |t| t.created_at < three_months_ago })

    $stderr.puts
    tweets
  end

  def load_timeline(timeline, *args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    @twitter.send(timeline, *args, { :count => 200, :include_rts => false }.merge(options))
  end

  def with_activity_data(tweets)
    tweets.tap do |tt|
      selected = tt.select { |t| t.retweet_count > MIN_RETWEET_COUNT }
      activities = @twitter.statuses_activity(selected.map(&:id))

      selected.zip(activities).each do |t, a|
        t.attrs.update(a.attrs)
      end
    end
  end

  def retweet(tweet)
    @twitter.retweet(tweet.id)
  end

  def interesting_tweet?(tweet)
    matches_keywords?(tweet) && tweet_activity_count(tweet) >= awesomeness_threshold(tweet.user)
  end

  def matches_keywords?(tweet)
    keywords_whitelist.any? { |k| tweet.text =~ k }
  end

  def keywords_whitelist
    @whitelist ||= File.readlines('keywords_whitelist.txt').map { |k| /\b#{k.strip}\b/i }
  end

  def tweet_activity_count(tweet)
    tweet.retweet_count + tweet.favoriters_count.to_i
  end

  def awesomeness_threshold(user)
    # this is a completely non-scientific formula calculated by trial and error
    # in order to set the bar higher for users that get retweeted a lot (@dhh, @rails).
    # should be around 20 for most people and then raise to ~30 for @rails and 50+ for @dhh.
    # the idea is that if you have an army of followers, everything you write gets retweeted and favorited

    17.5 + (user.followers_count ** 1.25) * 25 / 1_000_000
  end
end
