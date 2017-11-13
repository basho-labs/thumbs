# Thumbs

A simplified integration robot.

[<img src="https://ryanbrownhill.github.io/github-collab-pres/img/thumbsup.png" alt="Thumbs" data-canonical-src="https://ryanbrownhill.github.io/github-collab-pres/img/thumbsup.png" width="320" height="300" />](https://github.com/basho-labs/thumbs)

## What's this ?
Thumbs was created to help validate and merge pull requests. It was initially developed as a replacement for Bors.

Check out [this pull request](https://github.com/basho/riak_kv/pull/1639) for an example.

### Sponsors
The following wonderful companies have sponsored Thumbs:

[<img src="https://blog.profitbricks.com/wp-content/uploads/2015/12/Basho-Logo.jpg" alt="Basho" data-canonical-src="https://blog.profitbricks.com/wp-content/uploads/2015/12/Basho-Logo.jpg" width="100" height="100" />](https://basho.com)


### Credits
Without the guidance, support and contributions of the following people, Thumbs would have not been possible.

- Paul Hagan @ooshlablu 
- James Gorlick @paegun


# Setup and workflow
How to setup Thumbs for your repo and how it works.

#### 1) Enable Thumbs Webhook for your repository

##### Github: Enable Webhook
- Go to https://github.com/basho/YOUR-REPO/settings
- Click [Webhooks]
- Click [Add Webhook]
- Set Payload URL to: http://thumbs.cloud1.basho.com/webhook
- [checkbox] Send me everything

![Alt text](http://i.imgur.com/hyarJuX.png)

## 2) Deploy config

- Create a **.thumbs.yml** configuration file in your repo:

  ```yaml
  minimum_reviewers: 2  # minimum code reviews required before auto merge
  build_steps: # your custom build steps
   - "make"
   - "make test"
 
   # optional
  merge: false        # Set to true to enable automerging
  org_mode: true      # Only count code reviews from org members.
  timeout: 1800       # Let builds run for 30 minutes
  delete_branch: true # Delete pr branch after a merge
  # Specify a kerl otp release to run each set of build steps in. build_steps_<KERLRELEASE>
  # R16B01 R16B02 R16B03-1 R16B03 R16B 17.0-rc1 17.0-rc2 17.0 17.1 17.3 17.4 17.5 18.0 18.1 18.2 18.2.1 18.3 19.0 19.1
  build_steps_R16B03:
   - make test
  build_steps_18:
   - make test
  build_steps_19:
   - make pre_19test9-edgecase
  ```
  
- Add config and create pr branch:

  ```
  git add .thumbs.yml
  git commit -a -m"add .thumbs.yml"
  git checkout -b add_thumbs
  git push origin add_thumbs
  ```
 - Create pr at https://github.com/basho/YOUR-REPO/compare
 
##  Scenarios:
##  A new pull request
![Alt text](http://i.imgur.com/QrvXPoi.png)
##### Thumbs will :

1) Post parsed **.thumbs.yml** as comment.
![Alt text](http://i.imgur.com/QMGnL7i.png)
2) Try to merge PR branch onto target branch

3) Try to run build steps defined in **.thumbs.yml**

4) Report build status in PR comment.
![Alt text](http://i.imgur.com/zFrr7aR.png) 

##  A new comment
##### Thumbs will :
1) Count the number of comments containing +1 by org members other than the PR author. 

2) If minimum reviewers is met and build is valid, it will report reviewers count and attempt to merge.
![Alt text](http://i.imgur.com/4mj2SL7.png)

##  A new comment matching "thumbot retry"
##### Thumbs will :
Retry the tasks on the latest commit and rewrite its most recent PR comment to
reflect the current status.
![Screenshot of thumbot showing "In progress" above new comment of "thumbot retry"](http://i.imgur.com/20CFrkq.png)

## A new push
##### Thumbs will :
1) Rerun the build steps, reset the reviewer count and report build status
![Alt text](http://i.imgur.com/zFrr7aR.png)

## A build with errors
1) Displays the build report and will not automerge until a corrective, build passing push is made.
![Alt text](http://i.imgur.com/wOrjzKx.png)


## Local development and testing

## Start a local instance
```
> git clone https://github.com/basho-labs/thumbs.git
> cd thumbs
> bundler exec rackup
```
### Running Tests
```
> bundler exec ruby test/test.rb
```

### Manual Testing
##### In a separate window, start [ngrok](https://ngrok.com/) and collect the forwarding url
```
> ngrok http 4567
```
##### This will display the url to use, for example:

> Forwarding                    **http://699f13d5.ngrok.io** -> localhost:4567        

![Alt text](http://i.imgur.com/v3rSCTX.png)




