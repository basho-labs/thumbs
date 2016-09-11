# Thumbs

A simplified integration robot.

![Logo][logo]
[logo]: https://ryanbrownhill.github.io/github-collab-pres/img/thumbsup.png

### What does it do ?

It merges a pull request for you after doing validation.
 
 * (merge,build,test success and >=2 reviewers)

### How does it work ?

* When a pull request is created, 
    * a github webhook is called on /webhook
    * Thumbs will then merge, build and test and record status to a pr comment.
* When a comment is created,
    * a github webhook is called on /webhook
    * Thumbs checks to ensure PR contains a minimum of 2 non author review comments


## Setup

```
> git clone https://github.com/davidx/thumbs.git
> cd thumbs
> rake install
```
### test
For testing 
```
export GITHUB_USER=ted
export GITHUB_PASS=pear

export GITHUB_USER1=ted
export GITHUB_PASS1=pear

export GITHUB_USER2=bob
export GITHUB_PASS2=apple
```
### production
For normal operation, only a single set of github credentials is needed.
```
export GITHUB_USER=ted
export GITHUB_PASS=pear
```

### test webhooks 
##### In a separate window, start ngrok to collect the forwarding url
```
> ngrok -p 4567
```
##### This will display the url to use, for example:
```
Forwarding                    http://699f13d5.ngrok.io -> localhost:4567        
```

##### Go to the Github repo Settings->Webhooks & services" and click [Add webhook].
    Set the Payload URL to the one you just saved. add /webhook path. 

    Example: http://699f13d5.ngrok.io/webhook

    Checkbox: Send me Everything

## Test
```
> rake test DEBUG=true

[DEBUG] 2016-08-10 18:53:43 :Thumbs: thumbot/prtester 271 open Trying merge thumbot/prtester:PR#271 " Testing PR" 75c594d5518c2fcf4fb035ec97f01438a7bc9629 onto master
[DEBUG] 2016-08-10 18:53:43 :Thumbs: thumbot/prtester 271 open [ MAKE ] [OK] "cd /tmp/thumbs/thumbot_prtester_271 && make 2>&1"
[DEBUG] 2016-08-10 18:53:43 :Thumbs: thumbot/prtester 271 open [ MAKE_TEST ] [OK] "cd /tmp/thumbs/thumbot_prtester_271 && make test 2>&1"
[DEBUG] 2016-08-10 18:53:43 :Thumbs: thumbot/prtester 271 open [ MAKE_UNKNOWN_OPTION ] [ERROR] "cd /tmp/thumbs/thumbot_prtester_271 && make UNKNOWN_OPTION 2>&1"
[DEBUG] 2016-08-10 18:53:50 :Thumbs: thumbot/prtester 271 open determine valid_for_merge?
[DEBUG] 2016-08-10 18:53:53 :Thumbs: thumbot/prtester 271 open passed initial
[DEBUG] 2016-08-10 18:53:53 :Thumbs: thumbot/prtester 271 open 
[DEBUG] 2016-08-10 18:53:53 :Thumbs: thumbot/prtester 271 open result not :ok, not valid for merge
[DEBUG] 2016-08-10 18:53:53 :Thumbs: thumbot/prtester 271 open open?
.

Finished in 210.001074 seconds.
-------------------------------------------------------------------------------------------------------------------------------------------------------------------
9 tests, 84 assertions, 0 failures, 0 errors, 0 pendings, 0 omissions, 0 notifications
100% passed
-------------------------------------------------------------------------------------------------------------------------------------------------------------------
0.04 tests/s, 0.40 assertions/s
```

## Usage

```
> rake start
# Now create a pull request or leave a comment and watch the magic happen.
```

### Example: https://github.com/thumbot/prtester/pull/1


