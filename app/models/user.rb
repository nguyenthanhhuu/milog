class User < ApplicationRecord
  include Securable

  USERNAME_FORMAT = /[a-zA-Z0-9\-\_]{6,25}/
  EMAIL_FORMAT = /[\w\+\-\.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+/

  USERNAME_FORMAT_REGEXP = /\A#{ USERNAME_FORMAT.source }\z/
  EAMIL_FORMAT_REGEXP = /\A#{ EMAIL_FORMAT.source }\z/i

  TIPS_USERNAME_FORMAT_MSG = 'USERNAME_FORMAT'

  validates :username, :email, :password, presence: true
  validates :username, length: { in: 6..25 },
                       format: { with: USERNAME_FORMAT_REGEXP, message: TIPS_USERNAME_FORMAT_MSG },
                       uniqueness: { case_sensitive: false }
  validates :email,    length: { maximum: 255 },
                       format: { with: EAMIL_FORMAT_REGEXP },
                       uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 6 },
                       allow_nil: false
  validate :avatar_size

  has_many :articles,             dependent: :destroy
  has_many :user_categoryships,   dependent: :destroy
  has_many :categories,           through: :user_categoryships
  has_many :pictures,             dependent: :destroy
  has_many :comments,             dependent: :destroy
  has_one  :resume,               dependent: :destroy

  # 需引入gem bcrypt
  has_secure_password

  # 将avatar字段提交至AvatarUploader
  mount_uploader :avatar, AvatarUploader

  before_save :downcase_username_and_email
  after_create :generate_activation_digest, 
               :generate_letter_avatar,
               :generate_default_category_ship,
               :generate_a_resume

  attr_accessor :remember_token, :activation_token, :reset_password_token

  # 生成对应属性的加密字段digest, 并保留token
  def new_attr_digest(attribute)
    send "#{attribute}_token=", new_token
    update_digest attribute, digest_token(send("#{attribute}_token"))
  end

  def del_attr_digest(attribute)
    send "#{attribute}_token=", nil
    update_digest attribute, nil
  end

  # 判断有时效的加密字段是否还生效
  def digest_expired?(attribute, deadline = 2.hours)
    start_time = send "#{attribute}_at"
    Time.zone.now - start_time > deadline
  end

  # 激活用户
  def active
    del_attr_digest :activation
    update_attribute :activated, true
    update_attribute :activated_at, Time.zone.now      
  end

  # 生成激活字段, 记录用户状态
  def generate_activation_digest
    new_attr_digest :activation
    update_attribute :activated_at, Time.zone.now
  end

  # 生成重置密码字段
  def generate_reset_password_digest
    new_attr_digest :reset_password
    update_attribute :reset_password_at, Time.zone.now
  end

  # 用户已上传头像?
  def user_avatar?
    return false if avatar.file.nil?
    true
  end

  # 通过update_attribute实现update_attributes
  # 绕过验证
  def update_attributes_by_each(params)
    return false unless params
    params.each { |attri, value| update_attribute attri, value }
    true
  end

  # 用户发布文章所用的标签
  def tags
    Tag.find_by_sql "
      SELECT  DISTINCT tags.id, tags.name
      FROM    users, articles, article_tagships, tags
      WHERE   users.id = #{self.id}
      AND     users.id = articles.user_id
      AND     articles.id = article_tagships.article_id
      AND     article_tagships.tag_id = tags.id
      AND     articles.posted = true
    "
  end

  # 清除缓存图片
  def delete_cache_pictures
    pictures.where(posted: false).each do |picture|
      picture.destroy
    end
  end

  # 标记图片已使用
  def post_cache_pictures
    cache_pictures = pictures.where posted: false
    if cache_pictures.any?
      cache_pictures.update_all posted: true
    end
  end

  # 关联文章与图片
  # 当文章删除时, 可将文章使用的图片一起删除
  def post_cache_pictures_in_article(article)
    return if article.blank?
    cache_pictures = pictures.where posted: false
    if cache_pictures.any?
      cache_pictures.each do |picture|
        article.article_pictureships.create picture: picture
      end
      cache_pictures.update_all posted: true
    end
  end

  # 关联评论与图片
  def post_cache_pictures_in_comment(comment)
    return if comment.blank?
    cache_pictures = pictures.where posted: false 
    if cache_pictures.any?
      cache_pictures.each do |picture|
        comment.comment_pictureships.create picture: picture
      end
      cache_pictures.update_all posted: true
    end       
  end

  private
    def downcase_username_and_email
      username.downcase!
      email.downcase!
    end

    # 首字母头像 生成伪随机颜色
    def generate_letter_avatar
      color = '#' + [*'a'..'f', *'0'..'9'].sample(6).join
      update_attribute :avatar_color, color
    end

    # 限制头像大小
    def avatar_size
      if avatar.size > 1.megabytes
        errors.add :avatar, I18n.t("errors.avatar_too_big", size: 1)
      end      
    end

    # 生成与'默认'分类的关系
    def generate_default_category_ship
      category = Category.find_or_create_by name: 'default'
      self.user_categoryships.create category: category 
    end

    # 生成简历
    def generate_a_resume
      return if self.resume
      Resume.create user: self
    end
end
