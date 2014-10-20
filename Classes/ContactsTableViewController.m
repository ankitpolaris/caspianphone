/* ContactsTableViewController.m
 *
 * Copyright (C) 2012  Belledonne Comunications, Grenoble, France
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

#import "ContactsTableViewController.h"
#import "UIContactCell.h"
#import "LinphoneManager.h"
#import "PhoneMainView.h"
#import "UACellBackgroundView.h"
#import "UILinphone.h"
#import "Utils.h"

static NSString *caspianSupportFirstName = @"";
static NSString *caspianSupportLastName = @"";
static NSString *caspianSupportOrganization = @"One Call Caspian";
static NSString *caspianSupportPhoneLabel = @"One Call Caspian";

@implementation ContactsTableViewController

static void sync_address_book (ABAddressBookRef addressBook, CFDictionaryRef info, void *context);


#pragma mark - Lifecycle Functions

- (void)initContactsTableViewController {
	addressBookMap  = [[OrderedDictionary alloc] init];
	avatarMap = [[NSMutableDictionary alloc] init];

	addressBook = ABAddressBookCreateWithOptions(nil, nil);

	ABAddressBookRegisterExternalChangeCallback(addressBook, sync_address_book, self);
}

- (id)init {
	self = [super init];
	if (self) {
		[self initContactsTableViewController];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder {
	self = [super initWithCoder:decoder];
	if (self) {
		[self initContactsTableViewController];
	}
	return self;
}

- (void)dealloc {
	ABAddressBookUnregisterExternalChangeCallback(addressBook, sync_address_book, self);
	CFRelease(addressBook);
	[addressBookMap release];
	[avatarMap release];
	[super dealloc];
}


#pragma mark -

- (BOOL)contactHasValidSipDomain:(ABRecordRef)person {
	// Check if one of the contact' sip URI matches the expected SIP filter
	ABMultiValueRef personSipAddresses = ABRecordCopyValue(person, kABPersonInstantMessageProperty);
	BOOL match = false;
	NSString * filter = [ContactSelection getSipFilter];

	for(int i = 0; i < ABMultiValueGetCount(personSipAddresses) && !match; ++i) {
		CFDictionaryRef lDict = ABMultiValueCopyValueAtIndex(personSipAddresses, i);
		if(CFDictionaryContainsKey(lDict, kABPersonInstantMessageServiceKey)) {
			CFStringRef serviceKey = CFDictionaryGetValue(lDict, kABPersonInstantMessageServiceKey);

			if (CFStringCompare((CFStringRef)[LinphoneManager instance].contactSipField, serviceKey, kCFCompareCaseInsensitive) == 0) {
				match = true;
			}
		}  else {
			//check domain
			LinphoneAddress* address = linphone_address_new([(NSString*)CFDictionaryGetValue(lDict,kABPersonInstantMessageUsernameKey) UTF8String]);

			if (address) {
				NSString* domain = [NSString stringWithCString:linphone_address_get_domain(address)
													  encoding:[NSString defaultCStringEncoding]];

				if (([filter compare:@"*" options:NSCaseInsensitiveSearch] == NSOrderedSame)
					|| ([filter compare:domain options:NSCaseInsensitiveSearch] == NSOrderedSame)) {
					match = true;
				}
				linphone_address_destroy(address);
			}
		}
		CFRelease(lDict);
	}
	return match;
}

static int ms_strcmpfuz(const char * fuzzy_word, const char * sentence) {
	if (! fuzzy_word || !sentence) {
		return fuzzy_word == sentence;
	}
	const char * c = fuzzy_word;
	const char * within_sentence = sentence;
	for (; c != NULL && *c != '\0' && within_sentence != NULL; ++c) {
		within_sentence = strchr(within_sentence, *c);
		// Could not find c character in sentence. Abort.
		if (within_sentence == NULL) {
			break;
		}
		// since strchr returns the index of the matched char, move forward
		within_sentence++;
	}

	// If the whole fuzzy was found, returns 0. Otherwise returns number of characters left.
	return (within_sentence != NULL ? 0 : fuzzy_word + strlen(fuzzy_word) - c);
}

- (NSString *)nameOfContactWithFirstName:(NSString *)lLocalizedFirstName
                                lastName:(NSString *)lLocalizedLastName
                            organization:(NSString *)lLocalizedlOrganization {
    NSString *name = nil;
    if(lLocalizedFirstName.length > 0 && lLocalizedLastName.length > 0) {
        name = [NSString stringWithFormat:@"%@ %@", [(NSString *)lLocalizedFirstName retain], [(NSString *)lLocalizedLastName retain]];
    } else if(lLocalizedLastName.length > 0) {
        name = [NSString stringWithFormat:@"%@",[(NSString *)lLocalizedLastName retain]];
    } else if(lLocalizedFirstName.length > 0) {
        name = [NSString stringWithFormat:@"%@",[(NSString *)lLocalizedFirstName retain]];
    } else if(lLocalizedlOrganization.length > 0) {
        name = [NSString stringWithFormat:@"%@",[(NSString *)lLocalizedlOrganization retain]];
    }
    return name;
}

- (void)addContactWithName:(NSString *)name contactObject:(id)lPerson toAddressBookMap:(OrderedDictionary *)orderedAddressBookMap {
    if (name != nil && name.length > 0) {
        // Add the contact only if it fuzzy match filter too (if any)
        if ([ContactSelection getNameOrEmailFilter] == nil ||
            (ms_strcmpfuz([[[ContactSelection getNameOrEmailFilter] lowercaseString] UTF8String], [[name lowercaseString] UTF8String]) == 0)) {
            
            // Put in correct subDic
            NSString *firstChar = [[name substringToIndex:1] uppercaseString];
            /*
             if([firstChar characterAtIndex:0] < 'A' || [firstChar characterAtIndex:0] > 'Z') {
             firstChar = @"#";
             }
             */
            OrderedDictionary *subDic =[orderedAddressBookMap objectForKey:firstChar];
            if(subDic == nil) {
                subDic = [[[OrderedDictionary alloc] init] autorelease];
                [orderedAddressBookMap insertObject:subDic forKey:firstChar selector:@selector(caseInsensitiveCompare:)];
            }
            [subDic insertObject:lPerson forKey:name selector:@selector(caseInsensitiveCompare:)];
        }
    }
}

- (void)fillPerson:(id)lPerson
     withFirstName:(NSString *)firstName
          lastName:(NSString *)lastName
      organization:(NSString *)organization
       errorsArray:(NSMutableArray *)errorsArray {
    
    if (errorsArray.count > 0) {
        return;
    }

    CFErrorRef anError = NULL;

    ABRecordSetValue(lPerson, kABPersonFirstNameProperty, (__bridge CFStringRef)firstName, &anError);
    if (anError != NULL) {
        [errorsArray addObject:(__bridge NSError *)anError];
    }
    
    ABRecordSetValue(lPerson, kABPersonLastNameProperty, (__bridge CFStringRef)lastName, &anError);
    if (anError != NULL) {
        [errorsArray addObject:(__bridge NSError *)anError];
    }
    
    ABRecordSetValue(lPerson, kABPersonOrganizationProperty, (__bridge CFStringRef)organization, &anError);
    if (anError != NULL) {
        [errorsArray addObject:(__bridge NSError *)anError];
    }
}

- (void)addSupportPhoneNumber:(NSString *)phoneNumber
                    withLabel:(NSString *)label
                     toPerson:(id)lPerson
                  errorsArray:(NSMutableArray *)errorsArray {
    
    if (errorsArray.count > 0) {
        return;
    }
    
    ABMutableMultiValueRef lPhoneNumbers = ABRecordCopyValue(lPerson, kABPersonPhoneProperty);
    ABMutableMultiValueRef multiPhone;
    if (lPhoneNumbers != NULL) {
        multiPhone = ABMultiValueCreateMutableCopy(lPhoneNumbers);
        CFRelease(lPhoneNumbers);
    } else {
        multiPhone = ABMultiValueCreateMutable(kABPersonPhoneProperty);
    }
    if (multiPhone != NULL) {
        ABMultiValueAddValueAndLabel(multiPhone, [FastAddressBook caspianSupportPhoneNumber], (CFStringRef)caspianSupportPhoneLabel, NULL);
        ABRecordSetValue(lPerson, kABPersonPhoneProperty, multiPhone, nil);
        
        if(ABRecordGetRecordID(lPerson) == kABRecordInvalidID) {
            CFErrorRef anError = NULL;
            ABAddressBookAddRecord(addressBook, lPerson, &anError);
            if (anError != NULL) {
                [errorsArray addObject:(__bridge NSError *)anError];
            }
        }
    }
}

- (void)addAvatar:(UIImage *)image toPerson:(id)lPerson errorsArray:(NSMutableArray *)errorsArray {
    if (errorsArray.count > 0) {
        return;
    }
    
    CFErrorRef anError = NULL;

    NSData *imageData = [NSData dataWithData:UIImagePNGRepresentation(image)];
    if (!ABPersonSetImageData(lPerson, (CFDataRef)imageData, &anError)) {
        if (anError != NULL) {
            [errorsArray addObject:(__bridge NSError *)anError];
        }
    }
}

- (void)saveAddressBook:(ABAddressBookRef)addressBookRef errorsArray:(NSMutableArray *)errorsArray {
    if (errorsArray.count > 0) {
        return;
    }

    CFErrorRef anError = NULL;
    
    ABAddressBookSave(addressBookRef, &anError);
    if (anError != NULL) {
        [errorsArray addObject:(__bridge NSError *)anError];
    } else {
        [[LinphoneManager instance].fastAddressBook reload];
    }
}

- (void)loadData {
	[LinphoneLogger logc:LinphoneLoggerLog format:"Load contact list"];
	@synchronized (addressBookMap) {

		// Reset Address book
		[addressBookMap removeAllObjects];

        BOOL isCaspianSupportPresent = NO;
		NSArray *lContacts = (NSArray *)ABAddressBookCopyArrayOfAllPeople(addressBook);
		for (id lPerson in lContacts) {
			BOOL add = true;
			ABRecordRef person = (ABRecordRef)lPerson;

			// Do not add the contact directly if we set some filter
			if([ContactSelection getSipFilter] || [ContactSelection emailFilterEnabled]) {
				add = false;
			}
			if([ContactSelection getSipFilter] && [self contactHasValidSipDomain:person]) {
				add = true;
			}
			if (!add && [ContactSelection emailFilterEnabled]) {
				ABMultiValueRef personEmailAddresses = ABRecordCopyValue(person, kABPersonEmailProperty);
				// Add this contact if it has an email
				add = (ABMultiValueGetCount(personEmailAddresses) > 0);

				CFRelease(personEmailAddresses);
			}
            
            // Find Support Address Book Record
            isCaspianSupportPresent = isCaspianSupportPresent || [FastAddressBook isCaspianSupportRecord:person];

			if(add) {
				CFStringRef lFirstName = ABRecordCopyValue(person, kABPersonFirstNameProperty);
				CFStringRef lLocalizedFirstName = (lFirstName != nil)? ABAddressBookCopyLocalizedLabel(lFirstName): nil;
				CFStringRef lLastName = ABRecordCopyValue(person, kABPersonLastNameProperty);
				CFStringRef lLocalizedLastName = (lLastName != nil)? ABAddressBookCopyLocalizedLabel(lLastName): nil;
				CFStringRef lOrganization = ABRecordCopyValue(person, kABPersonOrganizationProperty);
				CFStringRef lLocalizedlOrganization = (lOrganization != nil)? ABAddressBookCopyLocalizedLabel(lOrganization): nil;
                
                /*
				NSString *name = nil;
				if(lLocalizedFirstName != nil && lLocalizedLastName != nil) {
					name=[NSString stringWithFormat:@"%@ %@", [(NSString *)lLocalizedFirstName retain], [(NSString *)lLocalizedLastName retain]];
				} else if(lLocalizedLastName != nil) {
					name=[NSString stringWithFormat:@"%@",[(NSString *)lLocalizedLastName retain]];
				} else if(lLocalizedFirstName != nil) {
					name=[NSString stringWithFormat:@"%@",[(NSString *)lLocalizedFirstName retain]];
				} else if(lLocalizedlOrganization != nil) {
					name=[NSString stringWithFormat:@"%@",[(NSString *)lLocalizedlOrganization retain]];
				}
                */
                
                NSString *name = [self nameOfContactWithFirstName:(__bridge NSString *)lLocalizedFirstName
                                                         lastName:(__bridge NSString *)lLocalizedLastName
                                                     organization:(__bridge NSString *)lLocalizedlOrganization];
                [self addContactWithName:name contactObject:lPerson toAddressBookMap:addressBookMap];
                
                /*
				if(name != nil && [name length] > 0) {
					// Add the contact only if it fuzzy match filter too (if any)
					if ([ContactSelection getNameOrEmailFilter] == nil ||
						(ms_strcmpfuz([[[ContactSelection getNameOrEmailFilter] lowercaseString] UTF8String], [[name lowercaseString] UTF8String]) == 0)) {

						// Put in correct subDic
						NSString *firstChar = [[name substringToIndex:1] uppercaseString];
						if([firstChar characterAtIndex:0] < 'A' || [firstChar characterAtIndex:0] > 'Z') {
							firstChar = @"#";
						}
						OrderedDictionary *subDic =[addressBookMap objectForKey:firstChar];
						if(subDic == nil) {
							subDic = [[[OrderedDictionary alloc] init] autorelease];
							[addressBookMap insertObject:subDic forKey:firstChar selector:@selector(caseInsensitiveCompare:)];
						}
						[subDic insertObject:lPerson forKey:name selector:@selector(caseInsensitiveCompare:)];
					}
				}
                */
        
				if(lLocalizedlOrganization != nil)
					CFRelease(lLocalizedlOrganization);
				if(lOrganization != nil)
					CFRelease(lOrganization);
				if(lLocalizedLastName != nil)
					CFRelease(lLocalizedLastName);
				if(lLastName != nil)
					CFRelease(lLastName);
				if(lLocalizedFirstName != nil)
					CFRelease(lLocalizedFirstName);
				if(lFirstName != nil)
					CFRelease(lFirstName);
			}
		}
        if (lContacts) {
			CFRelease(lContacts);
        }
        if (!isCaspianSupportPresent) {
            NSMutableArray *errorsArray = [NSMutableArray arrayWithArray:@[]];

            ABRecordRef lPerson = ABPersonCreate();
            [self fillPerson:lPerson
               withFirstName:caspianSupportFirstName
                    lastName:caspianSupportLastName
                organization:caspianSupportOrganization
                 errorsArray:errorsArray];

            [self addSupportPhoneNumber:[FastAddressBook caspianSupportPhoneNumber]
                              withLabel:caspianSupportPhoneLabel
                               toPerson:lPerson
                            errorsArray:errorsArray];

            [self addAvatar:[UIImage imageNamed:@"support-contact-avatar.png"] toPerson:lPerson errorsArray:errorsArray];
            
            [self saveAddressBook:addressBook errorsArray:errorsArray];
            
            if (errorsArray.count > 0) {
                NSString *errorString = @"";
                for (NSError *error in errorsArray) {
                    errorString = [errorString stringByAppendingString:[NSString stringWithFormat:@"%@\n", error.description]];
                }
                NSLog(@"Error while creating Caspian Support record: %@", errorString);
            } else {
                
                [avatarMap setObject:[UIImage imageNamed:@"support-contact-avatar.png"]
                              forKey:[NSNumber numberWithInt:ABRecordGetRecordID(lPerson)]];
                
                NSString *name = [self nameOfContactWithFirstName:caspianSupportFirstName
                                                         lastName:caspianSupportLastName
                                                     organization:caspianSupportOrganization];
                [self addContactWithName:name contactObject:lPerson toAddressBookMap:addressBookMap];
            }
            
            CFRelease(lPerson);
        }
	}
	[self.tableView reloadData];
}

static void sync_address_book (ABAddressBookRef addressBook, CFDictionaryRef info, void *context) {
	ContactsTableViewController* controller = (ContactsTableViewController*)context;
	ABAddressBookRevert(addressBook);
	[controller->avatarMap removeAllObjects];
	[controller loadData];
}

#pragma mark - ViewController Functions

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
}


#pragma mark - UITableViewDataSource Functions

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
	return [addressBookMap allKeys];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [addressBookMap count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [(OrderedDictionary *)[addressBookMap objectForKey: [addressBookMap keyAtIndex: section]] count];

}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *kCellId = @"UIContactCell";
	UIContactCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellId];
	if (cell == nil) {
		cell = [[[UIContactCell alloc] initWithIdentifier:kCellId] autorelease];

		// Background View
		UACellBackgroundView *selectedBackgroundView = [[[UACellBackgroundView alloc] initWithFrame:CGRectZero] autorelease];
		cell.selectedBackgroundView = selectedBackgroundView;
		[selectedBackgroundView setBackgroundColor:LINPHONE_TABLE_CELL_BACKGROUND_COLOR];
	}
	OrderedDictionary *subDic = [addressBookMap objectForKey: [addressBookMap keyAtIndex: [indexPath section]]];

	NSString *key = [[subDic allKeys] objectAtIndex:[indexPath row]];
	ABRecordRef contact = [subDic objectForKey:key];

	// Cached avatar
	UIImage *image = nil;
	id data = [avatarMap objectForKey:[NSNumber numberWithInt: ABRecordGetRecordID(contact)]];
	if(data == nil) {
		image = [FastAddressBook getContactImage:contact thumbnail:true];
		if(image != nil) {
			[avatarMap setObject:image forKey:[NSNumber numberWithInt: ABRecordGetRecordID(contact)]];
		} else {
			[avatarMap setObject:[NSNull null] forKey:[NSNumber numberWithInt: ABRecordGetRecordID(contact)]];
		}
	} else if(data != [NSNull null]) {
		image = data;
	}
	if(image == nil) {
		image = [UIImage imageNamed:@"profile-picture-small.png"];
	}
	[[cell avatarImage] setImage:image];

	[cell setContact: contact];
	return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return [addressBookMap keyAtIndex: section];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	OrderedDictionary *subDic = [addressBookMap objectForKey: [addressBookMap keyAtIndex: [indexPath section]]];
	ABRecordRef lPerson = [subDic objectForKey: [subDic keyAtIndex:[indexPath row]]];

	// Go to Contact details view
	ContactDetailsViewController *controller = DYNAMIC_CAST([[PhoneMainView instance] changeCurrentView:[ContactDetailsViewController compositeViewDescription] push:TRUE], ContactDetailsViewController);
	if(controller != nil) {
		if([ContactSelection getSelectionMode] != ContactSelectionModeEdit) {
			[controller setContact:lPerson];
		} else {
			[controller editContact:lPerson address:[ContactSelection getAddAddress]];
		}
	}
}


#pragma mark - UITableViewDelegate Functions

- (UITableViewCellEditingStyle)tableView:(UITableView *)aTableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	// Detemine if it's in editing mode
	if (self.editing) {
		return UITableViewCellEditingStyleDelete;
	}
	return UITableViewCellEditingStyleNone;
}

@end
