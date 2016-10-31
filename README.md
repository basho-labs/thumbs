# Thumbs

A simplified integration robot.

![Logo][logo]
[logo]: https://ryanbrownhill.github.io/github-collab-pres/img/thumbsup.png

# Setup and workflow
How to setup Thumbs for your repo and how it works.

## What's this ?
Thumbs was created to help validate and merge pull requests. It was initially created as a replacement for Bors.
## Setup
#### 1) Enable Thumbs Webhook for your repository

##### Github: Enable Webhook
- Go to https://github.com/basho/YOUR-REPO/settings
- Click [Webhooks]
- Click [Add Webhook]
- Set Payload URL to: http://thumbs.cloud1.basho.com/webhook
- [checkbox] Send me everything

![Alt text](http://i.imgur.com/hyarJuX.png)

## Or
#### Email devops@basho.com
ask to enable thumbs for your repo.

## 2) Deploy config

- Create a **.thumbs.yml** configuration file in your repo:

  ```yaml
  minimum_reviewers: 2  # minimum code reviews required before auto merge
  build_steps: # your custom build steps
   - "make"
   - "make test"
  merge: false  # set to true to enable automerging
  org_mode: true   # only count code reviews from org members.
  timeout: 1800 
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
> bundle exec rackup
```
### Running Tests
```
> bundle exec ruby test/test.rb
```

### Manual Testing
##### In a separate window, start [ngrok](https://ngrok.com/) and collect the forwarding url
```
> ngrok http 4567
```
##### This will display the url to use, for example:

> Forwarding                    **http://699f13d5.ngrok.io** -> localhost:4567        

![Alt text](http://i.imgur.com/v3rSCTX.png)

### Example: https://github.com/davidx/prtester/pull/295


