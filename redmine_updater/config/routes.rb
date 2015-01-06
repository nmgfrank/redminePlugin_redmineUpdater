match '/updater/index', :to => 'updater#index', :via => [:get, :post]
match '/updater/match', :to => 'updater#match', :via => [:get, :post]
match '/updater/pure_add', :to => 'updater#pure_add', :via => [:get, :post]
match '/updater/pure_update', :to => 'updater#pure_update', :via => [:get, :post]
match '/updater/wrong_csv', :to => 'updater#wrong_csv', :via => [:get, :post]

