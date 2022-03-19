OPTIONS_FILE=firebase_options.dart
FIREBASE_OPTIONS_REPO_ROOT=../firebase-options
default:
	echo nothing

populate:
	cp $(FIREBASE_OPTIONS_REPO_ROOT)/$(OPTIONS_FILE) lib/

commit:
	cp lib/$(OPTIONS_FILE) $(FIREBASE_OPTIONS_REPO_ROOT)
	cd $(FIREBASE_OPTIONS_REPO_ROOT) && git status
	cd $(FIREBASE_OPTIONS_REPO_ROOT) && git diff
	cd $(FIREBASE_OPTIONS_REPO_ROOT) && git add .
	cd $(FIREBASE_OPTIONS_REPO_ROOT) && git commit -m "Update $(OPTIONS_FILE)"

push:
	cd $(FIREBASE_OPTIONS_REPO_ROOT) && git push
