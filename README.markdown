LinkBack
========

LinkBack is an open source framework for Mac OS X that helps developers integrate content from other applications into their own. A user can paste content from any LinkBack-enabled application into another and reopen that content later for editing with just a double-click. Changes will automatically appear in the original document again when you save.

See <http://linkbackproject.org/>

This is based off LinkBack 1.0.3, plus changes and fixes The Omni Group has made over the years for our applications.

Checking out the source
-----------------------

This version of LinkBack depends on the OmniGroup Xcode configuration files, so you'll need a copy of the OmniGroup public frameworks:

  git clone git://github.com/omnigroup/OmniGroup

Also, internally, we keep the LinkBack source in a peer fold of "OmniGroup" called "Nisus", so you'll need:

  mkdir Nisus; cd Nisus
  git clone git://github.com/omnigroup/LinkBack

Alternatively, you can check out LinkBack inside the OmniGroup directory:

  cd OmniGroup
  git clone git://github.com/omnigroup/LinkBack


Configuring Xcode
------------------

The source is set up assuming a customized build products directory since that is what we do at Omni.

- Open Xcode's Building preferences pane
- Select "Customized location" for the "Place Build Products in:" option
- Enter a convenient path like /Users/Shared/your-login/Products

Building
--------

...

Enjoy!
