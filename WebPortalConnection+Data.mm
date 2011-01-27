/*=========================================================================
 Program:   OsiriX
 
 Copyright (c) OsiriX Team
 All rights reserved.
 Distributed under GNU - LGPL
 
 See http://www.osirix-viewer.com/copyright.html for details.
 
 This software is distributed WITHOUT ANY WARRANTY; without even
 the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 PURPOSE.
 =========================================================================*/

#import "WebPortalConnection+Data.h"
#import "WebPortalResponse.h"
#import "DicomAlbum.h"
#import "DicomDatabase.h"
#import "WebPortalUser.h"
#import "WebPortalSession.h"
#import "WebPortal.h"
#import "WebPortal+Email+Log.h"
#import "WebPortal+Databases.h"
#import "AsyncSocket.h"
#import "WebPortalDatabase.h"
#import "WebPortal+Databases.h"
#import "WebPortalConnection.h"
#import "NSUserDefaults+OsiriX.h"
#import "NSString+N2.h"
#import "NSImage+N2.h"
#import "DicomSeries.h"
#import "DicomStudy.h"
#import "WebPortalStudy.h"
#import "DicomImage.h"
#import "DCM.h"
#import "DCMPix.h"
#import "DCMTKStoreSCU.h"
#import "N2Alignment.h"



#import "BrowserController.h" // TODO: remove when badness solved
#import "BrowserControllerDCMTKCategory.h" // TODO: remove when badness solved



static NSTimeInterval StartOfDay(NSCalendarDate* day) {
	NSCalendarDate* start = [NSCalendarDate dateWithYear:day.yearOfCommonEra month:day.monthOfYear day:day.dayOfMonth hour:0 minute:0 second:0 timeZone:NULL];
	return start.timeIntervalSinceReferenceDate;
}



@implementation WebPortalConnection (Data)

+(NSArray*)MakeArray:(id)obj {
	if ([obj isKindOfClass:[NSArray class]])
		return obj;
	
	if (obj == nil)
		return [NSArray array];
	
	return [NSArray arrayWithObject:obj];
}

-(NSArray*)studyList_studiesForUser:(WebPortalUser*)luser outTitle:(NSString**)title {
	NSString* ignore = NULL;
	if (!title) title = &ignore;
	
	NSString* albumReq = [parameters objectForKey:@"album"];
	if (albumReq.length) {
		*title = [NSString stringWithFormat:NSLocalizedString(@"%@", @"Web portal, study list, title format (%@ is album name)"), albumReq];
		return [self.portal studiesForUser:luser album:albumReq sortBy:[parameters objectForKey:@"order"]];
	}
	
	NSString* browseReq = [parameters objectForKey:@"browse"];
	NSString* browseParameterReq = [parameters objectForKey:@"browseParameter"];
	
	NSPredicate* browsePredicate = NULL;
	
	if ([browseReq isEqual:@"newAddedStudies"] && browseParameterReq.doubleValue > 0)
	{
		*title = NSLocalizedString( @"New Available Studies", @"Web portal, study list, title");
		browsePredicate = [NSPredicate predicateWithFormat: @"dateAdded >= CAST(%lf, \"NSDate\")", browseParameterReq.doubleValue];
	}
	else
		if ([browseReq isEqual:@"today"])
		{
			*title = NSLocalizedString( @"Today", @"Web portal, study list, title");
			browsePredicate = [NSPredicate predicateWithFormat: @"date >= CAST(%lf, \"NSDate\")", StartOfDay(NSCalendarDate.calendarDate)];
		}
		else
			if ([browseReq isEqual:@"6hours"])
			{
				*title = NSLocalizedString( @"Last 6 Hours", @"Web portal, study list, title");
				NSCalendarDate *now = [NSCalendarDate calendarDate];
				browsePredicate = [NSPredicate predicateWithFormat: @"date >= CAST(%lf, \"NSDate\")", [[NSCalendarDate dateWithYear:[now yearOfCommonEra] month:[now monthOfYear] day:[now dayOfMonth] hour:[now hourOfDay]-6 minute:[now minuteOfHour] second:[now secondOfMinute] timeZone:nil] timeIntervalSinceReferenceDate]];
			}
			else
				if ([parameters objectForKey:@"search"])
				{
					*title = NSLocalizedString(@"Search Results", @"Web portal, study list, title");
					
					NSMutableString* search = [NSMutableString string];
					NSString *searchString = [parameters objectForKey:@"search"];
					
					NSArray* components = [searchString componentsSeparatedByString:@" "];
					NSMutableArray *newComponents = [NSMutableArray array];
					for (NSString *comp in components)
					{
						if (![comp isEqualToString:@""])
							[newComponents addObject:comp];
					}
					
					searchString = [newComponents componentsJoinedByString:@" "];
					
					[search appendFormat:@"name CONTAINS[cd] '%@'", searchString]; // [c] is for 'case INsensitive' and [d] is to ignore accents (diacritic)
					browsePredicate = [NSPredicate predicateWithFormat:search];
				}
				else
					if ([parameters objectForKey:@"searchID"])
					{
						*title = NSLocalizedString(@"Search Results", @"Web portal, study list, title");
						NSMutableString *search = [NSMutableString string];
						NSString *searchString = [NSString stringWithString:[parameters objectForKey:@"searchID"]];
						
						NSArray *components = [searchString componentsSeparatedByString:@" "];
						NSMutableArray *newComponents = [NSMutableArray array];
						for (NSString *comp in components)
						{
							if (![comp isEqualToString:@""])
								[newComponents addObject:comp];
						}
						
						searchString = [newComponents componentsJoinedByString:@" "];
						
						[search appendFormat:@"patientID CONTAINS[cd] '%@'", searchString]; // [c] is for 'case INsensitive' and [d] is to ignore accents (diacritic)
						browsePredicate = [NSPredicate predicateWithFormat:search];
					}
					else
						if ([parameters objectForKey:@"searchAccessionNumber"])
						{
							*title = NSLocalizedString(@"Search Results", @"Web portal, study list, title");
							NSMutableString *search = [NSMutableString string];
							NSString *searchString = [NSString stringWithString:[parameters objectForKey:@"searchAccessionNumber"]];
							
							NSArray *components = [searchString componentsSeparatedByString:@" "];
							NSMutableArray *newComponents = [NSMutableArray array];
							for (NSString *comp in components)
							{
								if (![comp isEqualToString:@""])
									[newComponents addObject:comp];
							}
							
							searchString = [newComponents componentsJoinedByString:@" "];
							
							[search appendFormat:@"accessionNumber CONTAINS[cd] '%@'", searchString]; // [c] is for 'case INsensitive' and [d] is to ignore accents (diacritic)
							browsePredicate = [NSPredicate predicateWithFormat:search];
						}
	
	if (!browsePredicate) {
		*title = NSLocalizedString(@"Study List", @"Web portal, study list, title");
		//browsePredicate = [NSPredicate predicateWithValue:YES];
	}	
	
	if ([parameters objectForKey:@"sortKey"])
		if ([[[self.portal.dicomDatabase entityForName:@"Study"] attributesByName] objectForKey:[parameters objectForKey:@"sortKey"]])
			[session setObject:[parameters objectForKey:@"sortKey"] forKey:@"StudiesSortKey"];
	if (![session objectForKey:@"StudiesSortKey"])
		[session setObject:@"name" forKey:@"StudiesSortKey"];
	
	return [self.portal studiesForUser:luser predicate:browsePredicate sortBy:[session objectForKey:@"StudiesSortKey"]];
}


-(DicomSeries*)series_requestedSeries {
	NSPredicate* browsePredicate;
	
	if ([parameters objectForKey:@"id"]) {
		if ([parameters objectForKey:@"studyID"])
			browsePredicate = [NSPredicate predicateWithFormat:@"study.studyInstanceUID == %@ AND seriesInstanceUID == %@", [parameters objectForKey:@"studyID"], [parameters objectForKey:@"id"]];
		else browsePredicate = [NSPredicate predicateWithFormat:@"seriesInstanceUID == %@", [parameters objectForKey:@"id"]];
	} else
		return NULL;
	
	NSArray* series = [self.portal seriesForUser:user predicate:browsePredicate];
	if (series.count)
		return series.lastObject;
	
	return NULL;
}

-(void)sendImages:(NSArray*)images toDicomNode:(NSDictionary*)dicomNodeDescription {
	[self.portal updateLogEntryForStudy: [[images lastObject] valueForKeyPath: @"series.study"] withMessage: [NSString stringWithFormat: @"DICOM Send to: %@", [dicomNodeDescription objectForKey:@"Address"]] forUser:user.name ip:asyncSocket.connectedHost];
	
	@try {
		NSDictionary* todo = [NSDictionary dictionaryWithObjectsAndKeys: [dicomNodeDescription objectForKey:@"Address"], @"Address", [dicomNodeDescription objectForKey:@"TransferSyntax"], @"TransferSyntax", [dicomNodeDescription objectForKey:@"Port"], @"Port", [dicomNodeDescription objectForKey:@"AETitle"], @"AETitle", [images valueForKey: @"completePath"], @"Files", nil];
		[NSThread detachNewThreadSelector:@selector(dicomSendThread:) toTarget:self withObject:todo];
	} @catch (NSException* e) {
		NSLog( @"Error: [WebPortalConnection sendImages:toDicomNode:] %@", e);
	}	
}

- (void)sendImagesToDicomNodeThread:(NSDictionary*)todo;
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	[session.sendLock lock];
	@try {
		[[[[DCMTKStoreSCU alloc] initWithCallingAET:[[NSUserDefaults standardUserDefaults] stringForKey: @"AETITLE"] 
										  calledAET:[todo objectForKey:@"AETitle"] 
										   hostname:[todo objectForKey:@"Address"] 
											   port:[[todo objectForKey:@"Port"] intValue] 
										filesToSend:[todo valueForKey: @"Files"]
									 transferSyntax:[[todo objectForKey:@"TransferSyntax"] intValue] 
										compression:1.0
									extraParameters:NULL] autorelease] run:self];
	} @catch (NSException* e) {
		NSLog(@"Error: [WebServiceConnection sendImagesToDicomNodeThread:] %@", e);
	} @finally {
		[session.sendLock unlock];
		[pool release];
	}
}

-(NSArray*)seriesSortDescriptors {
	return NULL; // TODO: update&return session series sort keys
}

-(void)getWidth:(CGFloat*)width height:(CGFloat*)height fromImagesArray:(NSArray*)imagesArray isiPhone:(BOOL)isiPhone {
	*width = 0;
	*height = 0;
	
	for ( NSNumber *im in [imagesArray valueForKey: @"width"])
		if ([im intValue] > *width) *width = [im intValue];
	
	for ( NSNumber *im in [imagesArray valueForKey: @"height"])
		if ([im intValue] > *height) *height = [im intValue];
	
	int maxWidth, maxHeight;
	int minWidth, minHeight;
	
	const int minResolution = 400;
	const int maxResolution = 800;

	minWidth = minResolution;
	minHeight = minResolution;
	
	if (isiPhone)
	{
		maxWidth = 300; // for the poster frame of the movie to fit in the iphone screen (vertically) // TODO: this made sense before Retina displays and iPads and NEEDS to be reconsidered
		maxHeight = 310;
	}
	else
	{
		maxWidth = maxResolution;
		maxHeight = maxResolution;
	}
	
	if (*width > maxWidth)
	{
		*height = *height * (float)maxWidth / (float) *width;
		*width = maxWidth;
	}
	
	if (*height > maxHeight)
	{
		*width = *width * (float)maxHeight / (float) *height;
		*height = maxHeight;
	}
	
	if (*width < minWidth)
	{
		*height = *height * (float)minWidth / (float) *width;
		*width = minWidth;
	}
	
	if (*height < minHeight)
	{
		*width = *width * (float)minHeight / (float) *height;
		*height = minHeight;
	}
}

const NSString* const GenerateMovieOutFileParamKey = @"outFile";
const NSString* const GenerateMovieFileNameParamKey = @"fileName";
const NSString* const GenerateMovieDicomImagesParamKey = @"dicomImageArray";
const NSString* const GenerateMovieIsIOSParamKey = @"isiPhone";

-(void)generateMovie:(NSMutableDictionary*)dict
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSString *outFile = [dict objectForKey:GenerateMovieOutFileParamKey];
	NSString *fileName = [dict objectForKey:GenerateMovieFileNameParamKey];
	NSArray *dicomImageArray = [dict objectForKey:GenerateMovieDicomImagesParamKey];
	BOOL isiPhone = [[dict objectForKey:GenerateMovieIsIOSParamKey] boolValue];
	
	NSMutableArray *imagesArray = [NSMutableArray array];
	
	@synchronized(self.portal.locks) {
		if (![self.portal.locks objectForKey:outFile])
			[self.portal.locks setObject:[[[NSRecursiveLock alloc] init] autorelease] forKey:outFile];
	}
		
	[[self.portal.locks objectForKey:outFile] lock];
	
	@try
	{
		if (![[NSFileManager defaultManager] fileExistsAtPath: outFile] || ([[dict objectForKey: @"rows"] intValue] > 0 && [[dict objectForKey: @"columns"] intValue] > 0))
		{
			NSMutableArray *pixs = [NSMutableArray arrayWithCapacity: [dicomImageArray count]];
			
			[[[BrowserController currentBrowser] managedObjectContext] lock];
			
			for (DicomImage *im in dicomImageArray)
			{
				DCMPix* dcmPix = [[DCMPix alloc] initWithPath: [im valueForKey:@"completePathResolved"] :0 :1 :nil :[[im valueForKey:@"frameID"] intValue] :[[im valueForKeyPath:@"series.id"] intValue] isBonjour:NO imageObj:im];
				
				if (dcmPix)
				{
					float curWW = 0;
					float curWL = 0;
					
					if ([[im valueForKey:@"series"] valueForKey:@"windowWidth"])
					{
						curWW = [[[im valueForKey:@"series"] valueForKey:@"windowWidth"] floatValue];
						curWL = [[[im valueForKey:@"series"] valueForKey:@"windowLevel"] floatValue];
					}
					
					if (curWW != 0)
						[dcmPix checkImageAvailble:curWW :curWL];
					else
						[dcmPix checkImageAvailble:[dcmPix savedWW] :[dcmPix savedWL]];
					
					[pixs addObject: dcmPix];
					[dcmPix release];
				}
				else
				{
					NSLog( @"****** dcmPix creation failed for file : %@", [im valueForKey:@"completePathResolved"]);
					float *imPtr = (float*)malloc( [[im valueForKey: @"width"] intValue] * [[im valueForKey: @"height"] intValue] * sizeof(float));
					for ( int i = 0 ;  i < [[im valueForKey: @"width"] intValue] * [[im valueForKey: @"height"] intValue]; i++)
						imPtr[ i] = i;
					
					dcmPix = [[DCMPix alloc] initWithData: imPtr :32 :[[im valueForKey: @"width"] intValue] :[[im valueForKey: @"height"] intValue] :0 :0 :0 :0 :0];
					[pixs addObject: dcmPix];
					[dcmPix release];
				}
			}
			
			[[[BrowserController currentBrowser] managedObjectContext] unlock];
			
			CGFloat width, height;
			
			if ([[dict objectForKey: @"rows"] intValue] > 0 && [[dict objectForKey: @"columns"] intValue] > 0)
			{
				width = [[dict objectForKey: @"columns"] intValue];
				height = [[dict objectForKey: @"rows"] intValue];
			}
			else 
				[self getWidth: &width height:&height fromImagesArray: dicomImageArray isiPhone: isiPhone];
			
			for (DCMPix *dcmPix in pixs)
			{
				NSImage *im = [dcmPix image];
				
				NSImage *newImage;
				
				if ([dcmPix pwidth] != width || [dcmPix pheight] != height)
					newImage = [im imageByScalingProportionallyToSize: NSMakeSize( width, height)];
				else
					newImage = im;
				
				[imagesArray addObject: newImage];
			}
			
			[[NSFileManager defaultManager] removeItemAtPath: [fileName stringByAppendingString: @" dir"] error: nil];
			[[NSFileManager defaultManager] createDirectoryAtPath: [fileName stringByAppendingString: @" dir"] attributes: nil];
			
			int inc = 0;
			for ( NSImage *img in imagesArray)
			{
				NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
				//[[img TIFFRepresentation] writeToFile: [[fileName stringByAppendingString: @" dir"] stringByAppendingPathComponent: [NSString stringWithFormat: @"%6.6d.tiff", inc]] atomically: YES];
				if ([outFile hasSuffix:@"swf"])
					[[[NSBitmapImageRep imageRepWithData:[img TIFFRepresentation]] representationUsingType:NSJPEGFileType properties:NULL] writeToFile:[[fileName stringByAppendingString:@" dir"] stringByAppendingPathComponent:[NSString stringWithFormat:@"%6.6d.jpg", inc]] atomically:YES];
				else
					[[img TIFFRepresentationUsingCompression: NSTIFFCompressionLZW factor: 1.0] writeToFile: [[fileName stringByAppendingString: @" dir"] stringByAppendingPathComponent: [NSString stringWithFormat: @"%6.6d.tiff", inc]] atomically: YES];
				inc++;
				[pool release];
			}
			
			NSTask *theTask = [[[NSTask alloc] init] autorelease];
			
			if (isiPhone)
			{
				@try
				{
					[theTask setArguments: [NSArray arrayWithObjects: fileName, @"writeMovie", [fileName stringByAppendingString: @" dir"], nil]];
					[theTask setLaunchPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Decompress"]];
					[theTask launch];
					
					while( [theTask isRunning]) [NSThread sleepForTimeInterval: 0.01];
				}
				@catch (NSException *e)
				{
					NSLog( @"***** writeMovie exception : %@", e);
				}
				
				theTask = [[[NSTask alloc] init] autorelease];
				
				@try
				{
					[theTask setArguments: [NSArray arrayWithObjects: outFile, @"writeMovieiPhone", fileName, nil]];
					[theTask setLaunchPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Decompress"]];
					[theTask launch];
					
					while( [theTask isRunning]) [NSThread sleepForTimeInterval: 0.01];
				}
				@catch (NSException *e)
				{
					NSLog( @"***** writeMovieiPhone exception : %@", e);
				}
			}
			else
			{
				@try
				{
					[theTask setArguments: [NSArray arrayWithObjects: outFile, @"writeMovie", [outFile stringByAppendingString: @" dir"], nil]];
					[theTask setLaunchPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Decompress"]];
					[theTask launch];
					
					while( [theTask isRunning]) [NSThread sleepForTimeInterval: 0.01];
				}
				@catch (NSException *e)
				{
					NSLog( @"***** writeMovie exception : %@", e);
				}
			}
		}
	}
	@catch (NSException *e)
	{
		NSLog( @"***** generate movie exception : %@", e);
	}
	
	[[self.portal.locks objectForKey:outFile] unlock];
	
	@synchronized(self.portal.locks) {
		if ([[self.portal.locks objectForKey:outFile] tryLock]) {
			[[self.portal.locks objectForKey: outFile] unlock];
			[self.portal.locks removeObjectForKey: outFile];
		}
	}
	
	[pool release];
}



-(NSData*)produceMovieForSeries:(DicomSeries*)series isiPhone:(BOOL)isiPhone fileURL:(NSString*)fileURL {
	NSString* path = @"/tmp/osirixwebservices";
	[NSFileManager.defaultManager confirmDirectoryAtPath:path];
	
	NSString* name = [NSString stringWithFormat:@"%@", [parameters objectForKey:@"id"]]; //[series valueForKey:@"id"];
	name = [name stringByAppendingFormat:@"-NBIM-%ld", series.dateAdded];
	
	NSMutableString* fileName = [NSMutableString stringWithString:name];
	[BrowserController replaceNotAdmitted:fileName];
	fileName = [NSMutableString stringWithString:[path stringByAppendingPathComponent: fileName]];
	[fileName appendFormat:@".%@", fileURL.pathExtension];
	
	NSString *outFile;
	
	if (isiPhone)
		outFile = [NSString stringWithFormat:@"%@2.m4v", [fileName stringByDeletingPathExtension]];
	else
		outFile = fileName;
	
	NSData* data = [NSData dataWithContentsOfFile: outFile];
	
	if (!data)
	{
		NSArray *dicomImageArray = [[series valueForKey:@"images"] allObjects];
		
		if ([dicomImageArray count] > 1)
		{
			@try
			{
				// Sort images with "instanceNumber"
				NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"instanceNumber" ascending:YES];
				NSArray *sortDescriptors = [NSArray arrayWithObject:sort];
				[sort release];
				dicomImageArray = [dicomImageArray sortedArrayUsingDescriptors: sortDescriptors];
				
			}
			@catch (NSException * e)
			{
				NSLog( @"%@", [e description]);
			}
			
			NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithBool: isiPhone], @"isiPhone", fileURL, @"fileURL", fileName, @"fileName", outFile, @"outFile", parameters, @"parameters", dicomImageArray, @"dicomImageArray", nil];
			
			[[[BrowserController currentBrowser] managedObjectContext] unlock];	
			
			[self generateMovie: dict];
			
			[[[BrowserController currentBrowser] managedObjectContext] lock];	

			
			data = [NSData dataWithContentsOfFile: outFile];
		}
	}
	
	return data;
}


#pragma mark HTML

-(void)processLoginHtml {
	response.templateString = [self.portal stringForPath:@"login.html"];
}

-(void)processIndexHtml {
	response.templateString = [self.portal stringForPath:@"index.html"];
}

-(void)processMainHtml {
//	if (!user || user.uploadDICOM.boolValue)
//		[self supportsPOST:NULL withSize:0];
	
	NSMutableArray* albums = [NSMutableArray array];
	for (NSArray* album in [[BrowserController currentBrowser] albumArray]) // TODO: badness here
		if (![[album valueForKey:@"name"] isEqualToString:NSLocalizedString(@"Database", nil)])
			[albums addObject:album];
	[response.tokens setObject:albums forKey:@"Albums"];
	[response.tokens setObject:[self.portal studiesForUser:user predicate:NULL] forKey:@"Studies"];
	
	response.templateString = [self.portal stringForPath:@"main.html"];
}

-(void)processStudyHtml {
	NSArray* studies = NULL;
	NSString* studyId = [parameters objectForKey:@"id"];
	if (studyId)
		studies = [self.portal studiesForUser:user predicate:[NSPredicate predicateWithFormat:@"studyInstanceUID == %@", studyId] sortBy:NULL];
	DicomStudy* study = studies.count == 1 ? [studies objectAtIndex:0] : NULL;
	if (!study)
		[response.tokens addError:NSLocalizedString(@"Invalid study selection.", @"Web Portal, study, error")];
	
	NSMutableArray* selectedSeries = [NSMutableArray array];
	for (NSString* selectedID in [WebPortalConnection MakeArray:[parameters objectForKey:@"selected"]])
		[selectedSeries addObjectsFromArray:[self.portal seriesForUser:user predicate:[NSPredicate predicateWithFormat:@"study.studyInstanceUID == %@ AND seriesInstanceUID == %@", studyId, selectedID]]];
	
	NSString* action = [parameters objectForKey:@"action"];
	
	if ([action isEqual:@"dicomSend"] && study) {
		NSArray* dicomDestinationArray = [[parameters objectForKey:@"dicomDestination"] componentsSeparatedByString:@":"];
		if (dicomDestinationArray.count >= 4) {
			NSMutableDictionary* dicomDestination = [NSMutableDictionary dictionary];
			[dicomDestination setObject:[dicomDestinationArray objectAtIndex:0] forKey:@"Address"];
			[dicomDestination setObject:[dicomDestinationArray objectAtIndex:1] forKey:@"Port"];
			[dicomDestination setObject:[dicomDestinationArray objectAtIndex:2] forKey:@"AETitle"];
			[dicomDestination setObject:[dicomDestinationArray objectAtIndex:3] forKey:@"TransferSyntax"];
			
			NSMutableArray* selectedImages = [NSMutableArray array];
			for (NSString* selectedID in [WebPortalConnection MakeArray:[parameters objectForKey:@"selected"]])
				for (DicomSeries* series in [self.portal seriesForUser:user predicate:[NSPredicate predicateWithFormat:@"study.studyInstanceUID == %@ AND seriesInstanceUID == %@", studyId, selectedID]])
					[selectedImages addObjectsFromArray:series.images.allObjects];
			
			if (selectedImages.count) {
				[self sendImages:selectedImages toDicomNode:dicomDestination];
				[response.tokens addMessage:[NSString stringWithFormat:NSLocalizedString(@"Dicom send to node %@ initiated.", @"Web Portal, study, dicom send, success"), [dicomDestination objectForKey:@"AETitle"]]];
			} else
				[response.tokens addError:[NSString stringWithFormat:NSLocalizedString(@"Dicom send failed: no images selected. Select one or more series.", @"Web Portal, study, dicom send, error")]];
		} else
			[response.tokens addError:[NSString stringWithFormat:NSLocalizedString(@"Dicom send failed: cannot identify node.", @"Web Portal, study, dicom send, error")]];
	}
	
	if ([action isEqual:@"shareStudy"] && study) {
		NSString* destUserName = [parameters objectForKey:@"shareStudyUser"];
		// find this user
		NSFetchRequest* req = [[[NSFetchRequest alloc] init] autorelease];
		req.entity = [self.portal.database entityForName:@"User"];
		req.predicate = [NSPredicate predicateWithFormat: @"name == %@", destUserName];
		NSArray* users = [self.portal.database.managedObjectContext executeFetchRequest:req error:NULL];
		if (users.count == 1) {
			// add study to specific study list for this user
			WebPortalUser* destUser = users.lastObject;
			if (![[destUser.studies.allObjects valueForKey:@"study"] containsObject:study]) {
				WebPortalStudy* wpStudy = [NSEntityDescription insertNewObjectForEntityForName:@"Study" inManagedObjectContext:self.portal.database.managedObjectContext];
				wpStudy.user = destUser;
				wpStudy.patientUID = study.patientUID;
				wpStudy.studyInstanceUID = study.studyInstanceUID;
				wpStudy.dateAdded = [NSDate dateWithTimeIntervalSinceReferenceDate:[[NSUserDefaults standardUserDefaults] doubleForKey:@"lastNotificationsDate"]];
				[self.portal.database save:NULL];
			}
			
			// Send the email
			[self.portal sendNotificationsEmailsTo: users aboutStudies:[NSArray arrayWithObject:study] predicate:NULL message:[N2NonNullString([parameters objectForKey:@"message"]) stringByAppendingFormat: @"\r\r\r%@\r\r%%URLsList%%", NSLocalizedString( @"To view this study, click on the following link:", nil)] replyTo:user.email customText:nil webServerAddress:self.portalAddress];
			[self.portal updateLogEntryForStudy: study withMessage: [NSString stringWithFormat: @"Share Study with User: %@", destUserName] forUser:user.name ip:asyncSocket.connectedHost];
			
			[response.tokens addMessage:[NSString stringWithFormat:NSLocalizedString(@"This study is now shared with <b>%@</b>.", @"Web Portal, study, share, ok (%@ is destUser.name)"), destUserName]];
		} else
			[response.tokens addError:[NSString stringWithFormat:NSLocalizedString(@"Study share failed: cannot identify user.", @"Web Portal, study, share, error")]];
	}
	
	[response.tokens setObject:[WebPortalProxy createWithObject:study transformer:DicomStudyTransformer.create] forKey:@"Study"];
	[response.tokens setObject:[NSString stringWithFormat:NSLocalizedString(@"%@", @"Web Portal, study, title format (%@ is study.name)"), study.name] forKey:@"PageTitle"];
	
	if (study) {
		[self.portal updateLogEntryForStudy:study withMessage:@"Browsing Study" forUser:user.name ip:asyncSocket.connectedHost];
		
		[self.portal.dicomDatabase.managedObjectContext lock];
		@try {
			[response.tokens setObject:self.requestIsMacOS?@"osirixzip":@"zip" forKey:@"zipextension"];
			
			NSString* browse = [parameters objectForKey:@"browse"];
			NSString* browseParameter = [parameters objectForKey:@"browseParameter"];
			NSString* search = [parameters objectForKey:@"search"];
			NSString* album = [parameters objectForKey:@"album"];
			NSString* studyListLinkLabel = NSLocalizedString(@"Study list", nil);
			if (search.length)
				studyListLinkLabel = [NSString stringWithFormat:NSLocalizedString(@"Search results for: %@", nil), search];
			else if (album.length)
				studyListLinkLabel = [NSString stringWithFormat:NSLocalizedString(@"Album: %@", nil), album];
			else if ([browse isEqualToString:@"6hours"])
				studyListLinkLabel = NSLocalizedString(@"Last 6 Hours", nil);
			else if ([browse isEqualToString:@"today"])
				studyListLinkLabel = NSLocalizedString(@"Today", nil);
			[response.tokens setObject:studyListLinkLabel forKey:@"BackLinkLabel"];
			
			// Series
			
			NSMutableArray* seriesArray = [NSMutableArray array];
			for (DicomSeries* s in [study.imageSeries sortedArrayUsingDescriptors:[self seriesSortDescriptors]])
				[seriesArray addObject:[WebPortalProxy createWithObject:s transformer:[DicomSeriesTransformer create]]];
			[response.tokens setObject:seriesArray forKey:@"Series"];
				
			// DICOM destinations

			NSMutableArray* dicomDestinations = [NSMutableArray array];
			if (!user || user.sendDICOMtoSelfIP.boolValue)
				[dicomDestinations addObject:[NSDictionary dictionaryWithObjectsAndKeys:
											  [asyncSocket connectedHost], @"address",
											  self.dicomCStorePortString, @"port",
											  @"This Computer", @"aeTitle",
											  self.requestIsIOS? @"5" : @"0", @"syntax",
											  self.requestIsIOS? @"This Computer" : [NSString stringWithFormat:@"This Computer [%@:%@]", [asyncSocket connectedHost], self.dicomCStorePortString], @"description",
											  NULL]];
			if (!user || user.sendDICOMtoAnyNodes.boolValue)
				for (NSDictionary* node in [DCMNetServiceDelegate DICOMServersListSendOnly:YES QROnly:NO])
					[dicomDestinations addObject:[NSDictionary dictionaryWithObjectsAndKeys:
												  [node objectForKey:@"Address"], @"address",
												  [node objectForKey:@"Port"], @"port",
												  [node objectForKey:@"AETitle"], @"aeTitle",
												  [node objectForKey:@"TransferSyntax"], @"syntax",
												  self.requestIsIOS? [node objectForKey:@"Description"] : [NSString stringWithFormat:@"%@ [%@:%@]", [node objectForKey:@"Description"], [node objectForKey:@"Address"], [node objectForKey:@"Port"]], @"description",
												  NULL]];
			[response.tokens setObject:dicomDestinations forKey:@"DicomDestinations"];
			
			// Share
			
			NSMutableArray* shareDestinations = [NSMutableArray array];
			if (!user || user.shareStudyWithUser.boolValue) {
				NSFetchRequest* req = [[[NSFetchRequest alloc] init] autorelease];
				req.entity = [self.portal.database entityForName:@"User"];
				req.predicate = [NSPredicate predicateWithValue:YES];
				NSArray* users = [[self.portal.database.managedObjectContext executeFetchRequest:req error:NULL] sortedArrayUsingDescriptors: [NSArray arrayWithObject: [[[NSSortDescriptor alloc] initWithKey: @"name" ascending: YES] autorelease]]];
				
				for (WebPortalUser* u in users)
					if (u != self.user)
						[shareDestinations addObject:[WebPortalProxy createWithObject:u transformer:[WebPortalUserTransformer create]]];
			}
			[response.tokens setObject:shareDestinations forKey:@"ShareDestinations"];

		} @catch (NSException* e) {
			NSLog(@"Error: [WebPortalResponse processStudyHtml:] %@", e);
		} @finally {
			[self.portal.dicomDatabase.managedObjectContext unlock];
		}
	}
		
	response.templateString = [self.portal stringForPath:@"study.html"];
}

-(void)processStudyListHtml {
	NSString* title = NULL;
	[response.tokens setObject:[self studyList_studiesForUser:self.user outTitle:&title] forKey:@"Studies"];	
	if (title) [response.tokens setObject:title forKey:@"PageTitle"];
	response.templateString = [self.portal stringForPath:@"studyList.html"];
}

-(void)processSeriesHtml {
	DicomSeries* series = [self series_requestedSeries];
	[response.tokens setObject:[WebPortalProxy createWithObject:series transformer:[DicomSeriesTransformer create]] forKey:@"Series"];
	[response.tokens setObject:series.name forKey:@"PageTitle"];
	[response.tokens setObject:series.study.name forKey:@"BackLinkLabel"];
	response.templateString = [self.portal stringForPath:@"series.html"];
}


-(void)processPasswordForgottenHtml {
	/*
	if (!portal.passwordRestoreAllowed) {
		response.statusCode = 404;
		return;
	}
	
	
	{
		
		NSMutableString *templateString = [self webServicesHTMLMutableString:@"password_forgotten.html"];
		
		NSString *message = @"";
		
		if ([[parameters valueForKey: @"what"] isEqualToString: @"restorePassword"])
		{
			NSString *email = [parameters valueForKey: @"email"];
			NSString *username = [parameters valueForKey: @"username"];
			
			// TRY TO FIND THIS USER
			if ([email length] > 0 || [username length] > 0)
			{
				[self.portal.database.managedObjectContext lock];
				
				@try
				{
					NSError *error = nil;
					NSFetchRequest *dbRequest = [[[NSFetchRequest alloc] init] autorelease];
					[dbRequest setEntity:[NSEntityDescription entityForName:@"User" inManagedObjectContext:self.portal.database.managedObjectContext]];
					
					if ([email length] > [username length])
						[dbRequest setPredicate: [NSPredicate predicateWithFormat: @"(email BEGINSWITH[cd] %@) AND (email ENDSWITH[cd] %@)", email, email]];
					else
						[dbRequest setPredicate: [NSPredicate predicateWithFormat: @"(name BEGINSWITH[cd] %@) AND (name ENDSWITH[cd] %@)", username, username]];
					
					error = nil;
					NSArray *users = [self.portal.database.managedObjectContext executeFetchRequest: dbRequest error:&error];
					
					if ([users count] >= 1)
					{
						for (WebPortalUser *user in users)
						{
							NSString *fromEmailAddress = [[NSUserDefaults standardUserDefaults] valueForKey: @"notificationsEmailsSender"];
							
							if (fromEmailAddress == nil)
								fromEmailAddress = @"";
							
							NSString *emailSubject = NSLocalizedString( @"Your password has been reset.", nil);
							NSMutableString *emailMessage = [NSMutableString stringWithString: @""];
							
							[user generatePassword];
							
							[emailMessage appendString: NSLocalizedString( @"Username:\r\r", nil)];
							[emailMessage appendString: [user valueForKey: @"name"]];
							[emailMessage appendString: @"\r\r"];
							[emailMessage appendString: NSLocalizedString( @"Password:\r\r", nil)];
							[emailMessage appendString: [user valueForKey: @"password"]];
							[emailMessage appendString: @"\r\r"];
							
							[portal updateLogEntryForStudy: nil withMessage: @"Password reseted for user" forUser: [user valueForKey: @"name"] ip: nil];
							
							[[CSMailMailClient mailClient] deliverMessage: [[[NSAttributedString alloc] initWithString: emailMessage] autorelease] headers: [NSDictionary dictionaryWithObjectsAndKeys: [user valueForKey: @"email"], @"To", fromEmailAddress, @"Sender", emailSubject, @"Subject", nil]];
							
							message = NSLocalizedString( @"You will receive shortly an email with a new password.", nil);
							
							[self.portal.database save:NULL];
						}
					}
					else
					{
						// To avoid someone scanning for the username
						[NSThread sleepForTimeInterval:3];
						
						[portal updateLogEntryForStudy: nil withMessage: @"Unknown user" forUser: [NSString stringWithFormat: @"%@ %@", username, email] ip: nil];
						
						message = NSLocalizedString( @"This user doesn't exist in our database.", nil);
					}
				}
				@catch( NSException *e)
				{
					NSLog( @"******* password_forgotten: %@", e);
				}
				
				[self.portal.database.managedObjectContext unlock];
			}
		}
		
		[WebPortalResponse mutableString:templateString block:@"MessageToWrite" setVisible:message.length];
		[templateString replaceOccurrencesOfString:@"%PageTitle%" withString:NSLocalizedString(@"Password Forgotten", @"Web portal, password forgotten, title")];
		
		[templateString replaceOccurrencesOfString: @"%Localized_Message%" withString:N2NonNullString(message)];
		
		data = [templateString dataUsingEncoding: NSUTF8StringEncoding];
		
		err = NO;
	}
	*/
}


-(void)processAccountHtml {/*
	if (!self.user) {
		self.statusCode = 404;
		return;
	}
	
	
	{
		NSString *message = @"";
		BOOL messageIsError = NO;
		
		if ([[parameters valueForKey: @"what"] isEqualToString: @"changePassword"])
		{
			NSString * previouspassword = [parameters valueForKey: @"previouspassword"];
			NSString * password = [parameters valueForKey: @"password"];
			
			if ([previouspassword isEqualToString:user.password])
			{
				if ([[parameters valueForKey: @"password"] isEqualToString: [parameters valueForKey: @"password2"]])
				{
					if ([password length] >= 4)
					{
						// We can update the user password
						[user setValue: password forKey: @"password"];
						message = NSLocalizedString( @"Password updated successfully !", nil);
						[portal updateLogEntryForStudy: nil withMessage: [NSString stringWithFormat: @"User changed his password"] forUser:self.user.name ip:wpc.asyncSocket.connectedHost];
					}
					else
					{
						message = NSLocalizedString( @"Password needs to be at least 4 characters !", nil);
						messageIsError = YES;
					}
				}
				else
				{
					message = NSLocalizedString( @"New passwords are not identical !", nil);
					messageIsError = YES;
				}
			}
			else
			{
				message = NSLocalizedString( @"Wrong current password !", nil);
				messageIsError = YES;
			}
		}
		
		if ([[parameters valueForKey: @"what"] isEqualToString: @"changeSettings"])
		{
			NSString * email = [parameters valueForKey: @"email"];
			NSString * address = [parameters valueForKey: @"address"];
			NSString * phone = [parameters valueForKey: @"phone"];
			
			[user setValue: email forKey: @"email"];
			[user setValue: address forKey: @"address"];
			[user setValue: phone forKey: @"phone"];
			
			if ([[[parameters valueForKey: @"emailNotification"] lowercaseString] isEqualToString: @"on"])
				[user setValue: [NSNumber numberWithBool: YES] forKey: @"emailNotification"];
			else
				[user setValue: [NSNumber numberWithBool: NO] forKey: @"emailNotification"];
			
			message = NSLocalizedString( @"Personal Information updated successfully !", nil);
		}
		
		NSMutableString *templateString = [self webServicesHTMLMutableString:@"account.html"];
		
		NSString *block = @"MessageToWrite";
		if (messageIsError)
		{
			block = @"ErrorToWrite";
			[WebPortalResponse mutableString:templateString block:@"MessageToWrite" setVisible:NO];
		}
		else
		{
			[WebPortalResponse mutableString:templateString block:@"ErrorToWrite" setVisible:NO];
		}
		
		[WebPortalResponse mutableString:templateString block:block setVisible:message.length];
		
		[templateString replaceOccurrencesOfString: @"%LocalizedLabel_MessageAccount%" withString:N2NonNullString(message)];
		
		[templateString replaceOccurrencesOfString: @"%name%" withString:N2NonNullString(user.name)];
		[templateString replaceOccurrencesOfString: @"%PageTitle%" withString:[NSString stringWithFormat:NSLocalizedString(@"User account for: %@", @"Web portal, account, title format (%@ is user.name)"), user.name]];
		
		[templateString replaceOccurrencesOfString: @"%email%" withString:N2NonNullString(user.email)];
		[templateString replaceOccurrencesOfString: @"%address%" withString:N2NonNullString(user.address)];
		[templateString replaceOccurrencesOfString: @"%phone%" withString:N2NonNullString(user.phone)];
		[templateString replaceOccurrencesOfString: @"%emailNotification%" withString: (user.emailNotification.boolValue?@"checked":@"")];
		
		data = [templateString dataUsingEncoding: NSUTF8StringEncoding];
		
		[self.portal.database save:NULL];
		
		err = NO;
	}
	*/
}






#pragma mark Administration HTML

-(void)processAdminIndexHtml {
	if (!user.isAdmin) {
		response.statusCode = 401;
		[self.portal updateLogEntryForStudy:NULL withMessage:@"Attempt to access admin area without being an admin" forUser:user.name ip:asyncSocket.connectedHost];
		return;
	}
	
	[response.tokens setObject:NSLocalizedString(@"Administration", @"Web Portal, admin, index, title") forKey:@"PageTitle"];
	
	NSFetchRequest* req = [[[NSFetchRequest alloc] init] autorelease];
	req.entity = [self.portal.database entityForName:@"User"];
	req.predicate = [NSPredicate predicateWithValue:YES];
	[response.tokens setObject:[[self.portal.database.managedObjectContext executeFetchRequest:req error:NULL] sortedArrayUsingDescriptors:[NSArray arrayWithObject:[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES]]] forKey:@"Users"];
	
	response.templateString = [self.portal stringForPath:@"admin/index.html"];
}

-(void)processAdminUserHtml {
	if (!user.isAdmin) {
		response.statusCode = 401;
		[self.portal updateLogEntryForStudy:NULL withMessage:@"Attempt to access admin area without being an admin" forUser:user.name ip:asyncSocket.connectedHost];
		return;
	}

	NSObject* luser = NULL;
	BOOL userRecycleParams = NO;
	NSString* action = [parameters objectForKey:@"action"];
	NSString* originalName = NULL;
	
	if ([action isEqual:@"delete"]) {
		originalName = [parameters objectForKey:@"originalName"];
		NSManagedObject* tempUser = [self.portal.database userWithName:originalName];
		if (!tempUser)
			[response.tokens addError:[NSString stringWithFormat:NSLocalizedString(@"Couldn't delete user <b>%@</b> because it doesn't exists.", @"Web Portal, admin, user edition, delete error (%@ is user.name)"), originalName]];
		else {
			[self.portal.database.managedObjectContext deleteObject:tempUser];
			[tempUser.managedObjectContext save:NULL];
			[response.tokens addMessage:[NSString stringWithFormat:NSLocalizedString(@"User <b>%@</b> successfully deleted.", @"Web Portal, admin, user edition, delete ok (%@ is user.name)"), originalName]];
		}
	}
	
	if ([action isEqual:@"save"]) {
		originalName = [parameters objectForKey:@"originalName"];
		WebPortalUser* webUser = [self.portal.database userWithName:originalName];
		if (!webUser) {
			[response.tokens addError:[NSString stringWithFormat:NSLocalizedString(@"Couldn't save changes for user <b>%@</b> because it doesn't exists.", @"Web Portal, admin, user edition, save error (%@ is user.name)"), originalName]];
			userRecycleParams = YES;
		} else {
			// NSLog(@"SAVE params: %@", parameters.description);
			
			NSString* name = [parameters objectForKey:@"name"];
			NSString* password = [parameters objectForKey:@"password"];
			NSString* studyPredicate = [parameters objectForKey:@"studyPredicate"];
			NSNumber* downloadZIP = [NSNumber numberWithBool:[[parameters objectForKey:@"downloadZIP"] isEqual:@"on"]];
			
			NSError* err;
			
			err = NULL;
			if (![webUser validateName:&name error:&err])
				[response.tokens addError:err.localizedDescription];
			err = NULL;
			if (![webUser validatePassword:&password error:&err])
				[response.tokens addError:err.localizedDescription];
			err = NULL;
			if (![webUser validateStudyPredicate:&studyPredicate error:&err])
				[response.tokens addError:err.localizedDescription];
			err = NULL;
			if (![webUser validateDownloadZIP:&downloadZIP error:&err])
				[response.tokens addError:err.localizedDescription];
			
			if (!response.tokens.errors.count) {
				webUser.name = name;
				webUser.password = password;
				webUser.email = [parameters objectForKey:@"email"];
				webUser.phone = [parameters objectForKey:@"phone"];
				webUser.address = [parameters objectForKey:@"address"];
				webUser.studyPredicate = studyPredicate;
				
				webUser.autoDelete = [NSNumber numberWithBool:[[parameters objectForKey:@"autoDelete"] isEqual:@"on"]];
				webUser.downloadZIP = downloadZIP;
				webUser.emailNotification = [NSNumber numberWithBool:[[parameters objectForKey:@"emailNotification"] isEqual:@"on"]];
				webUser.encryptedZIP = [NSNumber numberWithBool:[[parameters objectForKey:@"encryptedZIP"] isEqual:@"on"]];
				webUser.uploadDICOM = [NSNumber numberWithBool:[[parameters objectForKey:@"uploadDICOM"] isEqual:@"on"]];
				webUser.sendDICOMtoSelfIP = [NSNumber numberWithBool:[[parameters objectForKey:@"sendDICOMtoSelfIP"] isEqual:@"on"]];
				webUser.uploadDICOMAddToSpecificStudies = [NSNumber numberWithBool:[[parameters objectForKey:@"uploadDICOMAddToSpecificStudies"] isEqual:@"on"]];
				webUser.sendDICOMtoAnyNodes = [NSNumber numberWithBool:[[parameters objectForKey:@"sendDICOMtoAnyNodes"] isEqual:@"on"]];
				webUser.shareStudyWithUser = [NSNumber numberWithBool:[[parameters objectForKey:@"shareStudyWithUser"] isEqual:@"on"]];
				
				if (webUser.autoDelete.boolValue)
					webUser.deletionDate = [NSCalendarDate dateWithYear:[[parameters objectForKey:@"deletionDate_year"] integerValue] month:[[parameters objectForKey:@"deletionDate_month"] integerValue]+1 day:[[parameters objectForKey:@"deletionDate_day"] integerValue] hour:0 minute:0 second:0 timeZone:NULL];
				
				NSMutableArray* remainingStudies = [NSMutableArray array];
				for (NSString* studyObjectID in [[self.parameters objectForKey:@"remainingStudies"] componentsSeparatedByString:@","]) {
					studyObjectID = [studyObjectID.stringByTrimmingStartAndEnd stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
					
					WebPortalStudy* wpStudy = NULL;
					// this is Mac OS X 10.6 SnowLeopard only // wpStudy = [webUser.managedObjectContext existingObjectWithID:[webUser.managedObjectContext.persistentStoreCoordinator managedObjectIDForURIRepresentation:[NSURL URLWithString:studyObjectID]] error:NULL];
					for (WebPortalStudy* iwpStudy in webUser.studies)
						if ([iwpStudy.objectID.URIRepresentation.absoluteString isEqual:studyObjectID]) {
							wpStudy = iwpStudy;
							break;
						}
					
					if (wpStudy) [remainingStudies addObject:wpStudy];
					else NSLog(@"Warning: Web Portal user %@ is referencing a study with CoreData ID %@, which doesn't exist", self.user.name, studyObjectID);
				}
				for (WebPortalStudy* iwpStudy in webUser.studies.allObjects)
					if (![remainingStudies containsObject:iwpStudy])
						[webUser removeStudiesObject:iwpStudy];
				
				[webUser.managedObjectContext save:NULL];
				
				[response.tokens addMessage:[NSString stringWithFormat:NSLocalizedString(@"Changes for user <b>%@</b> successfully saved.", @"Web Portal, admin, user edition, save ok (%@ is user.name)"), webUser.name]];
				luser = webUser;
			} else
				userRecycleParams = YES;
		}
	}
	
	if ([action isEqual:@"new"]) {
		luser = [self.portal.database newUser];
	}
	
	if (!action) { // edit
		originalName = [self.parameters objectForKey:@"name"];
		luser = [self.portal.database userWithName:originalName];
		if (!luser)
			[response.tokens addError:[NSString stringWithFormat:NSLocalizedString(@"Couldn't find user with name <b>%@</b>.", @"Web Portal, admin, user edition, edit error (%@ is user.name)"), originalName]];
	}
	
	[response.tokens setObject:[NSString stringWithFormat:NSLocalizedString(@"User Administration: %@", @"Web Portal, admin, user edition, title (%@ is user.name)"), luser? [luser valueForKey:@"name"] : originalName] forKey:@"PageTitle"];
	if (luser)
		[response.tokens setObject:[WebPortalProxy createWithObject:luser transformer:[WebPortalUserTransformer create]] forKey:@"User"];
	else if (userRecycleParams) [response.tokens setObject:self.parameters forKey:@"User"];
	
	response.templateString = [self.portal stringForPath:@"admin/user.html"];
}

#pragma mark JSON

-(void)processStudyListJson {
	/*NSArray* studies = [self studyList_studiesForUser:self.user parameters:self.parameters outTitle:NULL]	
	
	[portal.dicomDatabase lock];
	@try {
		NSMutableArray* r = [NSMutableArray array];
		for (DicomStudy* study in studies) {
			NSMutableDictionary* s = [NSMutableDictionary dictionary];
			
			[s setObject:N2NonNullString(study.name) forKey:@"name"];
			[s setObject:[[NSNumber numberWithInt:study.series.count] stringValue] forKey:@"seriesCount"];
			[s setObject:[NSUserDefaults.dateFormatter stringFromDate:study.date] forKey:@"date"];
			[s setObject:N2NonNullString(study.studyName) forKey:@"studyName"];
			[s setObject:N2NonNullString(study.modality) forKey:@"modality"];
			
			NSString* stateText = study.stateText;
			if (stateText.intValue)
				stateText = [BrowserController.statesArray objectAtIndex:studyText.intValue];
			[s setObject:N2NonNullString(stateText) forKey:@"stateText"];

			[s setObject:N2NonNullString(study.studyInstanceUID) forKey:@"studyInstanceUID"];

			[r addObject:s];
		}
		
		return [r JSONRepresentation];
	} @catch (NSException* e) {
		NSLog(@"Error: [WebPortalResponse processStudyListJson:] %@", e);
	} @finally {
		[portal.dicomDatabase unlock];
	}*/
}

-(void)processSeriesJson {
	/*DicomSeries* series = [self series_requestedSeries];

	NSArray *imagesArray = [[[series lastObject] valueForKey:@"images"] allObjects];
	
	
	@try
	{
		// Sort images with "instanceNumber"
		NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"instanceNumber" ascending:YES];
		NSArray *sortDescriptors = [NSArray arrayWithObject:sort];
		[sort release];
		imagesArray = [imagesArray sortedArrayUsingDescriptors: sortDescriptors];
	}
	@catch (NSException * e)
	{
		NSLog( @"%@", [e description]);
	}
	
	
	
	
	
	NSMutableArray *jsonImagesArray = [NSMutableArray array];
	
	NSManagedObjectContext *context = [[BrowserController currentBrowser] managedObjectContext];
	[context lock];
	
	@try
	{
		for (DicomImage *image in images)
		{
			[jsonImagesArray addObject:N2NonNullString([image valueForKey:@"sopInstanceUID"])];
		}
	}
	@catch (NSException *e)
	{
		NSLog( @"***** jsonImageListForImages exception: %@", e);
	}
	
	[context unlock];
	
	return [jsonImagesArray JSONRepresentation];
	
	
	
	
	
	
	
	
	data = [json dataUsingEncoding:NSUTF8StringEncoding];
	err = NO;*/		
}

-(void)processAlbumsJson {/*
	
	NSMutableArray *jsonAlbumsArray = [NSMutableArray array];
	
	NSArray	*albumArray = [[BrowserController currentBrowser] albumArray];
	for (NSManagedObject *album in albumArray)
	{
		if (![[album valueForKey:@"name"] isEqualToString: NSLocalizedString(@"Database", nil)])
		{
			NSMutableDictionary *albumDictionary = [NSMutableDictionary dictionary];
			
			[albumDictionary setObject:N2NonNullString([album valueForKey:@"name"]) forKey:@"name"];
			[albumDictionary setObject:N2NonNullString([[album valueForKey:@"name"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]) forKey:@"nameURLSafe"];
			
			if ([[album valueForKey:@"smartAlbum"] intValue] == 1)
				[albumDictionary setObject:@"SmartAlbum" forKey:@"type"];
			else
				[albumDictionary setObject:@"Album" forKey:@"type"];
			
			[jsonAlbumsArray addObject:albumDictionary];
		}
	}
	
	NSString *json = [jsonAlbumsArray JSONRepresentation];
	
		data = [json dataUsingEncoding:NSUTF8StringEncoding];
		err = NO;
	*/
}

-(void)processSeriesListJson {/*

	{
		NSPredicate *browsePredicate;
		if ([[parameters allKeys] containsObject:@"id"])
		{
			browsePredicate = [NSPredicate predicateWithFormat:@"studyInstanceUID == %@", [parameters objectForKey:@"id"]];
		}
		else
			browsePredicate = [NSPredicate predicateWithValue:NO];
		
		
		NSArray *studies = [self studiesForPredicate:browsePredicate];
		
		if ([studies count] == 1)
		{
			NSArray *series = [[studies objectAtIndex:0] valueForKey:@"imageSeries"];
			
			
			
			
			
			
			NSMutableArray *jsonSeriesArray = [NSMutableArray array];
			
			NSManagedObjectContext *context = [[BrowserController currentBrowser] managedObjectContext];
			
			[context lock];
			
			@try
			{
				for (DicomSeries *s in series)
				{
					NSMutableDictionary *seriesDictionary = [NSMutableDictionary dictionary];
					
					[seriesDictionary setObject:N2NonNullString([s valueForKey:@"seriesInstanceUID"]) forKey:@"seriesInstanceUID"];
					[seriesDictionary setObject:N2NonNullString([s valueForKey:@"seriesDICOMUID"]) forKey:@"seriesDICOMUID"];
					
					NSArray *dicomImageArray = [[s valueForKey:@"images"] allObjects];
					DicomImage *im;
					if ([dicomImageArray count] == 1)
						im = [dicomImageArray lastObject];
					else
						im = [dicomImageArray objectAtIndex:[dicomImageArray count]/2];
					
					[seriesDictionary setObject:[im valueForKey:@"sopInstanceUID"] forKey:@"keyInstanceUID"];
					
					[jsonSeriesArray addObject:seriesDictionary];
				}
			}
			@catch (NSException *e)
			{
				NSLog( @"******* jsonSeriesListForSeries exception: %@", e);
			}
			[context unlock];
			
			NSString *json =  [jsonSeriesArray JSONRepresentation];
			
			
			
			
			data = [json dataUsingEncoding:NSUTF8StringEncoding];
			err = NO;
		}
		else err = YES;
	}
	*/
}


#pragma mark WADO

#define WadoCacheSize 2000

-(NSMutableDictionary*)wadoCache {
	const NSString* const WadoCacheKey = @"WADO Cache";
	NSMutableDictionary* dict = [self.portal.cache objectForKey:WadoCacheKey];
	if (!dict || ![dict isKindOfClass:NSMutableDictionary.class])
		[self.portal.cache setObject: dict = [NSMutableDictionary dictionaryWithCapacity:WadoCacheSize] forKey:WadoCacheKey];
	return dict;
}

// wado?requestType=WADO&studyUID=XXXXXXXXXXX&seriesUID=XXXXXXXXXXX&objectUID=XXXXXXXXXXX
// 127.0.0.1:3333/wado?requestType=WADO&frameNumber=1&studyUID=2.16.840.1.113669.632.20.1211.10000591592&seriesUID=1.3.6.1.4.1.19291.2.1.2.2867252960399100001&objectUID=1.3.6.1.4.1.19291.2.1.3.2867252960616100004
-(void)processWado {
	if (!self.portal.wadoEnabled) {
		self.response.statusCode = 403;
		[self.response setDataWithString:NSLocalizedString(@"OsiriX cannot fulfill your request because the WADO service is disabled.", NULL)];
		return;
	}
	
	if (![[[parameters objectForKey:@"requestType"] lowercaseString] isEqual:@"wado"]) {
		self.response.statusCode = 404;
		return;
	}
	
	NSString* studyUID = [parameters objectForKey:@"studyUID"];
	NSString* seriesUID = [parameters objectForKey:@"seriesUID"];
	NSString* objectUID = [parameters objectForKey:@"objectUID"];
	
	if (objectUID == nil)
		NSLog(@"***** WADO with objectUID == nil -> wado will fail");
	
	NSString* contentType = [[[[parameters objectForKey:@"contentType"] lowercaseString] componentsSeparatedByString: @","] objectAtIndex: 0];
	int rows = [[parameters objectForKey:@"rows"] intValue];
	int columns = [[parameters objectForKey:@"columns"] intValue];
	int windowCenter = [[parameters objectForKey:@"windowCenter"] intValue];
	int windowWidth = [[parameters objectForKey:@"windowWidth"] intValue];
	int frameNumber = [[parameters objectForKey:@"frameNumber"] intValue];	// -> OsiriX stores frames as images
	int imageQuality = DCMLosslessQuality;
	
	NSString* imageQualityParam = [parameters objectForKey:@"imageQuality"];
	if (imageQualityParam) {
		int imageQualityParamInt = imageQualityParam.intValue;
		if (imageQualityParamInt > 80)
			imageQuality = DCMLosslessQuality;
		else if (imageQualityParamInt > 60)
			imageQuality = DCMHighQuality;
		else if (imageQualityParamInt > 30)
			imageQuality = DCMMediumQuality;
		else if (imageQualityParamInt >= 0)
			imageQuality = DCMLowQuality;
	}
	
	NSString* transferSyntax = [[parameters objectForKey:@"transferSyntax"] lowercaseString];
	NSString* useOrig = [[parameters objectForKey:@"useOrig"] lowercaseString];
	
	NSFetchRequest* dbRequest = [[[NSFetchRequest alloc] init] autorelease];
	dbRequest.entity = [self.portal.dicomDatabase entityForName:@"Study"];
	
	@try {
		NSMutableDictionary *imageCache = nil;
		NSArray *images = nil;
		
		if (self.wadoCache.count > WadoCacheSize)
			[self.wadoCache removeAllObjects]; // TODO: not actually a good way to limit the cache
		
		if (contentType.length == 0 || [contentType isEqualToString:@"image/jpeg"] || [contentType isEqualToString:@"image/png"] || [contentType isEqualToString:@"image/gif"] || [contentType isEqualToString:@"image/jp2"])
			imageCache = [self.wadoCache objectForKey:[objectUID stringByAppendingFormat:@"%d", frameNumber]];
		
		if (!imageCache) {
			if (studyUID)
				[dbRequest setPredicate: [NSPredicate predicateWithFormat: @"studyInstanceUID == %@", studyUID]];
			else
				[dbRequest setPredicate: [NSPredicate predicateWithValue: YES]];
			
			NSArray *studies = [self.portal.dicomDatabase.managedObjectContext executeFetchRequest:dbRequest error:NULL];
			
			if ([studies count] == 0)
				NSLog( @"****** WADO Server : study not found");
			
			if ([studies count] > 1)
				NSLog( @"****** WADO Server : more than 1 study with same uid");
			
			NSArray *allSeries = [[[studies lastObject] valueForKey: @"series"] allObjects];
			
			if (seriesUID)
				allSeries = [allSeries filteredArrayUsingPredicate: [NSPredicate predicateWithFormat:@"seriesDICOMUID == %@", seriesUID]];
			
			NSArray *allImages = [NSArray array];
			for ( id series in allSeries)
				allImages = [allImages arrayByAddingObjectsFromArray: [[series valueForKey: @"images"] allObjects]];
			
			NSPredicate *predicate = [NSComparisonPredicate predicateWithLeftExpression: [NSExpression expressionForKeyPath: @"compressedSopInstanceUID"] rightExpression: [NSExpression expressionForConstantValue: [DicomImage sopInstanceUIDEncodeString: objectUID]] customSelector: @selector( isEqualToSopInstanceUID:)];
			NSPredicate *N2NonNullStringPredicate = [NSPredicate predicateWithFormat:@"compressedSopInstanceUID != NIL"];
			
			images = [[allImages filteredArrayUsingPredicate: N2NonNullStringPredicate] filteredArrayUsingPredicate: predicate];
			
			if ([images count] > 1)
			{
				images = [images sortedArrayUsingDescriptors: [NSArray arrayWithObject: [[[NSSortDescriptor alloc] initWithKey: @"instanceNumber" ascending:YES] autorelease]]];
				
				if (frameNumber < [images count])
					images = [NSArray arrayWithObject: [images objectAtIndex: frameNumber]];
			}
			
			if ([images count])
			{
				[self.portal updateLogEntryForStudy: [studies lastObject] withMessage:@"WADO Send" forUser:self.user.name ip:self.asyncSocket.connectedHost];
			}
		}
		
		if ([images count] || imageCache != nil)
		{
			if ([contentType isEqualToString: @"application/dicom"])
			{
				if ([useOrig isEqualToString: @"true"] || [useOrig isEqualToString: @"1"] || [useOrig isEqualToString: @"yes"])
				{
					response.data = [NSData dataWithContentsOfFile: [[images lastObject] valueForKey: @"completePath"]];
				}
				else
				{
					DCMTransferSyntax *ts = [[[DCMTransferSyntax alloc] initWithTS: transferSyntax] autorelease];
					
					if ([ts isEqualToTransferSyntax: [DCMTransferSyntax JPEG2000LosslessTransferSyntax]] ||
						[ts isEqualToTransferSyntax: [DCMTransferSyntax JPEG2000LossyTransferSyntax]] ||
						[ts isEqualToTransferSyntax: [DCMTransferSyntax JPEGBaselineTransferSyntax]] ||
						[ts isEqualToTransferSyntax: [DCMTransferSyntax JPEGLossless14TransferSyntax]] ||
						[ts isEqualToTransferSyntax: [DCMTransferSyntax JPEGBaselineTransferSyntax]])
					{
						
					}
					else // Explicit VR Little Endian
						ts = [DCMTransferSyntax ExplicitVRLittleEndianTransferSyntax];
					
					response.data = [[BrowserController currentBrowser] getDICOMFile:[[images lastObject] valueForKey: @"completePath"] inSyntax: ts.transferSyntax quality: imageQuality];
				}
				//err = NO;
			}
			else if ([contentType isEqualToString: @"video/mpeg"])
			{
				DicomImage *im = [images lastObject];
				
				NSArray *dicomImageArray = [[[im valueForKey: @"series"] valueForKey:@"images"] allObjects];
				
				@try
				{
					// Sort images with "instanceNumber"
					NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"instanceNumber" ascending:YES];
					NSArray *sortDescriptors = [NSArray arrayWithObject:sort];
					[sort release];
					dicomImageArray = [dicomImageArray sortedArrayUsingDescriptors: sortDescriptors];
					
				}
				@catch (NSException * e)
				{
					NSLog( @"%@", [e description]);
				}
				
				if ([dicomImageArray count] > 1)
				{
					NSString *path = @"/tmp/osirixwebservices";
					[[NSFileManager defaultManager] createDirectoryAtPath:path attributes:nil];
					
					NSString *name = [NSString stringWithFormat:@"%@",[parameters objectForKey:@"id"]];
					name = [name stringByAppendingFormat:@"-NBIM-%d", [dicomImageArray count]];
					
					NSMutableString *fileName = [NSMutableString stringWithString: [path stringByAppendingPathComponent:name]];
					
					[BrowserController replaceNotAdmitted: fileName];
					
					[fileName appendString:@".mov"];
					
					NSString *outFile;
					if (self.requestIsIOS)
						outFile = [NSString stringWithFormat:@"%@2.m4v", [fileName stringByDeletingPathExtension]];
					else
						outFile = fileName;
					
					NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithBool: self.requestIsIOS], GenerateMovieIsIOSParamKey, /*fileURL, @"fileURL",*/ fileName, GenerateMovieFileNameParamKey, outFile, GenerateMovieOutFileParamKey, parameters, @"parameters", dicomImageArray, GenerateMovieDicomImagesParamKey, [NSNumber numberWithInt: rows], @"rows", [NSNumber numberWithInt: columns], @"columns", nil];
					
					[self.portal.dicomDatabase.managedObjectContext unlock];
					[self generateMovie:dict];
					[self.portal.dicomDatabase.managedObjectContext lock];
					
					self.response.data = [NSData dataWithContentsOfFile:outFile];
					
				}
			}
			else // image/jpeg
			{
				DCMPix* dcmPix = [imageCache valueForKey: @"dcmPix"];
				
				if (dcmPix)
				{
					// It's in the cache
				}
				else if ([images count] > 0)
				{
					DicomImage *im = [images lastObject];
					
					dcmPix = [[[DCMPix alloc] initWithPath: [im valueForKey: @"completePathResolved"] :0 :1 :nil :frameNumber :[[im valueForKeyPath:@"series.id"] intValue] isBonjour:NO imageObj:im] autorelease];
					
					if (dcmPix == nil)
					{
						NSLog( @"****** dcmPix creation failed for file : %@", [im valueForKey:@"completePathResolved"]);
						float *imPtr = (float*)malloc( [[im valueForKey: @"width"] intValue] * [[im valueForKey: @"height"] intValue] * sizeof(float));
						for ( int i = 0 ;  i < [[im valueForKey: @"width"] intValue] * [[im valueForKey: @"height"] intValue]; i++)
							imPtr[ i] = i;
						
						dcmPix = [[[DCMPix alloc] initWithData: imPtr :32 :[[im valueForKey: @"width"] intValue] :[[im valueForKey: @"height"] intValue] :0 :0 :0 :0 :0] autorelease];
					}
					
					imageCache = [NSMutableDictionary dictionaryWithObject: dcmPix forKey: @"dcmPix"];
					
					[self.wadoCache setObject: imageCache forKey: [objectUID stringByAppendingFormat: @"%d", frameNumber]];
				}
				
				if (dcmPix)
				{
					NSImage *image = nil;
					NSManagedObject *im =  [dcmPix imageObj];
					
					float curWW = windowWidth;
					float curWL = windowCenter;
					
					if (curWW == 0 && [[im valueForKey:@"series"] valueForKey:@"windowWidth"])
					{
						curWW = [[[im valueForKey:@"series"] valueForKey:@"windowWidth"] floatValue];
						curWL = [[[im valueForKey:@"series"] valueForKey:@"windowLevel"] floatValue];
					}
					
					if (curWW == 0)
					{
						curWW = [dcmPix savedWW];
						curWL = [dcmPix savedWL];
					}
					
					self.response.data = [imageCache objectForKey: [NSString stringWithFormat: @"%@ %f %f %d %d %d", contentType, curWW, curWL, columns, rows, frameNumber]];
					
					if (!self.response.data.length)
					{
						[dcmPix checkImageAvailble: curWW :curWL];
						
						image = [dcmPix image];
						float width = [image size].width;
						float height = [image size].height;
						
						int maxWidth = columns;
						int maxHeight = rows;
						
						BOOL resize = NO;
						
						if (width > maxWidth && maxWidth > 0)
						{
							height =  height * maxWidth / width;
							width = maxWidth;
							resize = YES;
						}
						
						if (height > maxHeight && maxHeight > 0)
						{
							width = width * maxHeight / height;
							height = maxHeight;
							resize = YES;
						}
						
						NSImage *newImage;
						
						if (resize)
							newImage = [image imageByScalingProportionallyToSize: NSMakeSize(width, height)];
						else
							newImage = image;
						
						NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:[newImage TIFFRepresentation]];
						NSDictionary *imageProps = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat: 0.8] forKey:NSImageCompressionFactor];
						
						if ([contentType isEqualToString: @"image/gif"])
							self.response.data = [imageRep representationUsingType: NSGIFFileType properties:imageProps];
						else if ([contentType isEqualToString: @"image/png"])
							self.response.data = [imageRep representationUsingType: NSPNGFileType properties:imageProps];
						else if ([contentType isEqualToString: @"image/jp2"])
							self.response.data = [imageRep representationUsingType: NSJPEG2000FileType properties:imageProps];
						else
							self.response.data = [imageRep representationUsingType: NSJPEGFileType properties:imageProps];
						
						[imageCache setObject:self.response.data forKey: [NSString stringWithFormat: @"%@ %f %f %d %d %d", contentType, curWW, curWL, columns, rows, frameNumber]];
					}
					
					// Alessandro: I'm not sure here, from Joris' code it seems WADO must always return HTTP 200, eventually with length 0..
					self.response.data;
					self.response.statusCode = 0;
				}
			}
		}
		else NSLog( @"****** WADO Server : image uid not found !");
		
		if (!self.response.data)
			self.response.data = [NSData data];

	} @catch (NSException * e) {
		NSLog(@"Error: [WebPortalResponse processWado:] %@", e);
		self.response.statusCode = 500;
	}
}

#pragma mark Weasis

-(void)processWeasisJnlp {
	if (!self.portal.weasisEnabled) {
		response.statusCode = 404;
		return;
	}
	
	[response.tokens setObject:self.portalURL forKey:@"WebServerAddress"];
	
	response.templateString = [self.portal stringForPath:@"weasis.jnlp"];
	response.mimeType = @"application/x-java-jnlp-file";
}

-(void)processWeasisXml {
	if (!self.portal.weasisEnabled) {
		response.statusCode = 404;
		return;
	}
	
	NSString* studyInstanceUID = [self.parameters objectForKey:@"StudyInstanceUID"];
	NSString* seriesInstanceUID = [self.parameters objectForKey:@"SeriesInstanceUID"];
	NSArray* selectedSeries = [WebPortalConnection MakeArray:[self.parameters objectForKey:@"selected"]];
	
	NSMutableArray* requestedStudies = [NSMutableArray arrayWithCapacity:8];
	NSMutableArray* requestedSeries = [NSMutableArray arrayWithCapacity:64];
	
	// find requosted core data objects
	if (studyInstanceUID)
		[requestedStudies addObjectsFromArray:[self.portal studiesForUser:self.user predicate:[NSPredicate predicateWithFormat:@"studyInstanceUID == %@", studyInstanceUID] sortBy:NULL]];
	if (seriesInstanceUID)
		[requestedSeries addObjectsFromArray:[self.portal seriesForUser:self.user predicate:[NSPredicate predicateWithFormat:@"seriesInstanceUID == %@", seriesInstanceUID]]];
	for (NSString* selSeriesInstanceUID in selectedSeries)
		[requestedSeries addObjectsFromArray:[self.portal seriesForUser:self.user predicate:[NSPredicate predicateWithFormat:@"seriesInstanceUID == %@", selSeriesInstanceUID]]];
	
	NSMutableArray* patientIds = [NSMutableArray arrayWithCapacity:2];
	NSMutableArray* studies = [NSMutableArray arrayWithCapacity:8];
	NSMutableArray* series = [NSMutableArray arrayWithCapacity:64];
	
	for (DicomStudy* study in requestedStudies) {
		if (![studies containsObject:study])
			[studies addObject:study];
		if (![patientIds containsObject:study.patientID])
			[patientIds addObject:study.patientID];
		for (DicomSeries* serie in study.series)
			if (![series containsObject:serie])
				[series addObject:serie];
	}
	
	for (DicomSeries* serie in requestedSeries) {
		if (![studies containsObject:serie.study])
			[studies addObject:serie.study];
		if (![patientIds containsObject:serie.study.patientID])
			[patientIds addObject:serie.study.patientID];
		if (![series containsObject:serie])
			[series addObject:serie];
	}
	
	// filter by user rights
	if (self.user) {
		studies = (NSMutableArray*) [self.portal studiesForUser:self.user predicate:[NSPredicate predicateWithValue:YES] sortBy:nil];// is not mutable, but we won't mutate it anymore
	}
	
	// produce XML
	NSString* baseXML = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\"?><wado_query wadoURL=\"%@/wado\"></wado_query>", self.portalURL];
	NSXMLDocument* doc = [[NSXMLDocument alloc] initWithXMLString:baseXML options:NSXMLDocumentIncludeContentTypeDeclaration|NSXMLDocumentTidyXML error:NULL];
	[doc setCharacterEncoding:@"UTF-8"];
	
	NSDateFormatter* dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
	dateFormatter.dateFormat = @"dd-MM-yyyy";
	NSDateFormatter* timeFormatter = [[[NSDateFormatter alloc] init] autorelease];
	timeFormatter.dateFormat = @"HH:mm:ss";	
	
	for (NSString* patientId in patientIds) {
		NSXMLElement* patientNode = [NSXMLNode elementWithName:@"Patient"];
		[patientNode addAttribute:[NSXMLNode attributeWithName:@"PatientID" stringValue:patientId]];
		BOOL patientDataSet = NO;
		[doc.rootElement addChild:patientNode];
		
		for (DicomStudy* study in studies)
			if ([study.patientID isEqual:patientId]) {
				NSXMLElement* studyNode = [NSXMLNode elementWithName:@"Study"];
				[studyNode addAttribute:[NSXMLNode attributeWithName:@"StudyInstanceUID" stringValue:study.studyInstanceUID]];
				[studyNode addAttribute:[NSXMLNode attributeWithName:@"StudyDescription" stringValue:study.studyName]];
				[studyNode addAttribute:[NSXMLNode attributeWithName:@"StudyDate" stringValue:[dateFormatter stringFromDate:study.date]]];
				[studyNode addAttribute:[NSXMLNode attributeWithName:@"StudyTime" stringValue:[timeFormatter stringFromDate:study.date]]];
				[studyNode addAttribute:[NSXMLNode attributeWithName:@"AccessionNumber" stringValue:study.accessionNumber]];
				[studyNode addAttribute:[NSXMLNode attributeWithName:@"StudyID" stringValue:study.id]]; // ?
				[studyNode addAttribute:[NSXMLNode attributeWithName:@"ReferringPhysicianName" stringValue:study.referringPhysician]];
				[patientNode addChild:studyNode];
				
				for (DicomSeries* serie in series)
					if (serie.study == study) {
						NSXMLElement* serieNode = [NSXMLNode elementWithName:@"Series"];
						[serieNode addAttribute:[NSXMLNode attributeWithName:@"SeriesInstanceUID" stringValue:serie.seriesDICOMUID]];
						[serieNode addAttribute:[NSXMLNode attributeWithName:@"SeriesDescription" stringValue:serie.seriesDescription]];
						[serieNode addAttribute:[NSXMLNode attributeWithName:@"SeriesNumber" stringValue:[serie.id stringValue]]]; // ?
						[serieNode addAttribute:[NSXMLNode attributeWithName:@"Modality" stringValue:serie.modality]];
						[studyNode addChild:serieNode];
						
						for (DicomImage* image in serie.images) {
							NSXMLElement* instanceNode = [NSXMLNode elementWithName:@"Instance"];
							[instanceNode addAttribute:[NSXMLNode attributeWithName:@"SOPInstanceUID" stringValue:image.sopInstanceUID]];
							[instanceNode addAttribute:[NSXMLNode attributeWithName:@"InstanceNumber" stringValue:[image.instanceNumber stringValue]]];
							[serieNode addChild:instanceNode];
						}
					}
				
				if (!patientDataSet) {
					[patientNode addAttribute:[NSXMLNode attributeWithName:@"PatientName" stringValue:study.name]];
					[patientNode addAttribute:[NSXMLNode attributeWithName:@"PatientBirthDate" stringValue:[dateFormatter stringFromDate:study.dateOfBirth]]];
					[patientNode addAttribute:[NSXMLNode attributeWithName:@"PatientSex" stringValue:study.patientSex]];
				}
			}
	}
	
	[response setDataWithString:[[doc autorelease] XMLString]];
	response.mimeType = @"text/xml";	
}

#pragma mark Other

-(void)processReport {
	/*
	
	{
		NSPredicate *browsePredicate;
		if ([[parameters allKeys] containsObject:@"id"])
		{
			browsePredicate = [NSPredicate predicateWithFormat:@"studyInstanceUID == %@", [parameters objectForKey:@"id"]];
		}
		else
			browsePredicate = [NSPredicate predicateWithValue:NO];
		
		NSArray *studies = [self studiesForPredicate:browsePredicate];
		
		if ([studies count] == 1)
		{
			[portal updateLogEntryForStudy: [studies lastObject] withMessage: @"Download Report" forUser:self.user.name ip:wpc.asyncSocket.connectedHost];
			
			NSString *reportFilePath = [[studies lastObject] valueForKey:@"reportURL"];
			
			NSString *reportType = [reportFilePath pathExtension];
			
			if ([reportType isEqualToString: @"pages"])
			{
				NSString *zipFileName = [NSString stringWithFormat:@"%@.zip", [reportFilePath lastPathComponent]];
				// zip the directory into a single archive file
				NSTask *zipTask   = [[NSTask alloc] init];
				[zipTask setLaunchPath:@"/usr/bin/zip"];
				[zipTask setCurrentDirectoryPath:[[reportFilePath stringByDeletingLastPathComponent] stringByAppendingString:@"/"]];
				if ([reportType isEqualToString:@"pages"])
					[zipTask setArguments:[NSArray arrayWithObjects: @"-q", @"-r" , zipFileName, [reportFilePath lastPathComponent], nil]];
				else
					[zipTask setArguments:[NSArray arrayWithObjects: zipFileName, [reportFilePath lastPathComponent], nil]];
				[zipTask launch];
				while( [zipTask isRunning]) [NSThread sleepForTimeInterval: 0.01];
				int result = [zipTask terminationStatus];
				[zipTask release];
				
				if (result==0)
				{
					reportFilePath = [[reportFilePath stringByDeletingLastPathComponent] stringByAppendingFormat:@"/%@", zipFileName];
				}
				
				data = [NSData dataWithContentsOfFile: reportFilePath];
				
				[[NSFileManager defaultManager] removeFileAtPath:reportFilePath handler:nil];
				
				if (data)
					err = NO;
			}
			else
			{
				data = [NSData dataWithContentsOfFile: reportFilePath];
				
				if (data)
					err = NO;
			}
		}
	}
	
	*/
}

#define ThumbnailsCacheSize 20

-(NSMutableDictionary*)thumbnailsCache {
	const NSString* const ThumbsCacheKey = @"Thumbnails Cache";
	NSMutableDictionary* dict = [self.portal.cache objectForKey:ThumbsCacheKey];
	if (!dict || ![dict isKindOfClass:NSMutableDictionary.class])
		[self.portal.cache setObject: dict = [NSMutableDictionary dictionaryWithCapacity:ThumbnailsCacheSize] forKey:ThumbsCacheKey];
	return dict;
}

-(void)processThumbnail {
	NSPredicate *browsePredicate = nil;
	NSString *seriesInstanceUID = nil, *studyInstanceUID = nil;
	
	if ([[parameters allKeys] containsObject:@"id"])
	{
		if ([[parameters allKeys] containsObject:@"studyID"])
		{
			if (self.thumbnailsCache.count > ThumbnailsCacheSize)
				[self.thumbnailsCache removeAllObjects];
			
			if ([self.thumbnailsCache objectForKey: [parameters objectForKey:@"studyID"]])
			{
				NSDictionary *seriesThumbnail = [self.thumbnailsCache objectForKey: [parameters objectForKey:@"studyID"]];
				
				if ([seriesThumbnail objectForKey: [parameters objectForKey:@"id"]])
					response.data = [seriesThumbnail objectForKey: [parameters objectForKey:@"id"]];
			}
			
			browsePredicate = [NSPredicate predicateWithFormat:@"study.studyInstanceUID == %@", [parameters objectForKey:@"studyID"]];// AND seriesInstanceUID == %@", [parameters objectForKey:@"studyID"], [parameters objectForKey:@"id"]];
			
			studyInstanceUID = [parameters objectForKey:@"studyID"];
			seriesInstanceUID = [parameters objectForKey:@"id"];
		}
		else
		{
			browsePredicate = [NSPredicate predicateWithFormat:@"study.studyInstanceUID == %@", [parameters objectForKey:@"id"]];
			studyInstanceUID = [parameters objectForKey:@"id"];
		}
	}
	else
		browsePredicate = [NSPredicate predicateWithValue:NO];
	
	if (!response.data.length)
	{
		NSArray *series = [self.portal seriesForUser:self.user predicate:browsePredicate];
		
		if ([series count]  > 0)
		{
			NSMutableDictionary *seriesThumbnails = [NSMutableDictionary dictionary];
			
			for ( DicomSeries *s in series)
			{
				NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData: [s valueForKey:@"thumbnail"]];
				
				NSDictionary *imageProps = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:1.0] forKey:NSImageCompressionFactor];
				
				NSData *dataThumbnail = [imageRep representationUsingType:NSPNGFileType properties:imageProps];
				
				if (dataThumbnail && [s valueForKey: @"seriesInstanceUID"])
				{
					[seriesThumbnails setObject: dataThumbnail forKey: [s valueForKey: @"seriesInstanceUID"]];
					
					if ([seriesInstanceUID isEqualToString: [s valueForKey: @"seriesInstanceUID"]])
						response.data = dataThumbnail;
				}
			}
			
			if (studyInstanceUID && seriesThumbnails)
				[self.thumbnailsCache setObject: seriesThumbnails forKey: studyInstanceUID];
		}
	}
}

-(void)processSeriesPdf {/*
	NSPredicate *browsePredicate;
	if ([[parameters allKeys] containsObject:@"id"])
	{
		if ([[parameters allKeys] containsObject:@"studyID"])
			browsePredicate = [NSPredicate predicateWithFormat:@"study.studyInstanceUID == %@ AND seriesInstanceUID == %@", [parameters objectForKey:@"studyID"], [parameters objectForKey:@"id"]];
		else
			browsePredicate = [NSPredicate predicateWithFormat:@"study.studyInstanceUID == %@", [parameters objectForKey:@"id"] ];
	}
	else
		browsePredicate = [NSPredicate predicateWithValue:NO];
	
	NSArray *series = [self seriesForPredicate: browsePredicate];
	
	if ([series count] == 1)
	{
		if ([DCMAbstractSyntaxUID isPDF: [[series lastObject] valueForKey: @"seriesSOPClassUID"]])
		{
			DCMObject *dcmObject = [DCMObject objectWithContentsOfFile: [[[[series lastObject] valueForKey: @"images"] anyObject] valueForKey: @"completePath"]  decodingPixelData:NO];
			
			if ([[dcmObject attributeValueWithName:@"SOPClassUID"] isEqualToString: [DCMAbstractSyntaxUID pdfStorageClassUID]])
			{
				data = [dcmObject attributeValueWithName:@"EncapsulatedDocument"];
				
				if (data)
					err = NO;
			}
		}
		
		if ([DCMAbstractSyntaxUID isStructuredReport: [[series lastObject] valueForKey: @"seriesSOPClassUID"]])
		{
			if ([[NSFileManager defaultManager] fileExistsAtPath: @"/tmp/dicomsr_osirix/"] == NO)
				[[NSFileManager defaultManager] createDirectoryAtPath: @"/tmp/dicomsr_osirix/" attributes: nil];
			
			NSString *htmlpath = [[@"/tmp/dicomsr_osirix/" stringByAppendingPathComponent: [[[[[series lastObject] valueForKey: @"images"] anyObject] valueForKey: @"completePath"] lastPathComponent]] stringByAppendingPathExtension: @"html"];
			
			if ([[NSFileManager defaultManager] fileExistsAtPath: htmlpath] == NO)
			{
				NSTask *aTask = [[[NSTask alloc] init] autorelease];		
				[aTask setEnvironment:[NSDictionary dictionaryWithObject:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"/dicom.dic"] forKey:@"DCMDICTPATH"]];
				[aTask setLaunchPath: [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"/dsr2html"]];
				[aTask setArguments: [NSArray arrayWithObjects: [[[[series lastObject] valueForKey: @"images"] anyObject] valueForKey: @"completePath"], htmlpath, nil]];		
				[aTask launch];
				[aTask waitUntilExit];		
				[aTask interrupt];
			}
			
			if ([[NSFileManager defaultManager] fileExistsAtPath: [htmlpath stringByAppendingPathExtension: @"pdf"]] == NO)
			{
				NSTask *aTask = [[[NSTask alloc] init] autorelease];
				[aTask setLaunchPath: [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"/Decompress"]];
				[aTask setArguments: [NSArray arrayWithObjects: htmlpath, @"pdfFromURL", nil]];		
				[aTask launch];
				[aTask waitUntilExit];		
				[aTask interrupt];
			}
			
			data = [NSData dataWithContentsOfFile: [htmlpath stringByAppendingPathExtension: @"pdf"]];
			
			if (data)
				err = NO;
		}
	}
	
	if (err)
	{
		data = [NSData data];
		err = NO;
	}*/
}


-(void)processZip {/*

	{
		NSPredicate *browsePredicate;
		if ([[parameters allKeys] containsObject:@"id"])
		{
			if ([[parameters allKeys] containsObject:@"studyID"])
				browsePredicate = [NSPredicate predicateWithFormat:@"study.studyInstanceUID == %@ AND seriesInstanceUID == %@", [parameters objectForKey:@"studyID"], [parameters objectForKey:@"id"]];
			else
				browsePredicate = [NSPredicate predicateWithFormat:@"study.studyInstanceUID == %@", [parameters objectForKey:@"id"]];
		}
		else
			browsePredicate = [NSPredicate predicateWithValue:NO];
		
		NSArray *series = [self seriesForPredicate:browsePredicate];
		
		NSMutableArray *imagesArray = [NSMutableArray array];
		for ( DicomSeries *s in series)
			[imagesArray addObjectsFromArray: [[s valueForKey:@"images"] allObjects]];
		
		if ([imagesArray count])
		{
			if (user.encryptedZIP.boolValue)
				[portal updateLogEntryForStudy: [[series lastObject] valueForKey: @"study"] withMessage: @"Download encrypted DICOM ZIP" forUser:self.user.name ip:wpc.asyncSocket.connectedHost];
			else
				[portal updateLogEntryForStudy: [[series lastObject] valueForKey: @"study"] withMessage: @"Download DICOM ZIP" forUser:self.user.name ip:wpc.asyncSocket.connectedHost];
			
			@try
			{
				NSString *srcFolder = @"/tmp";
				NSString *destFile = @"/tmp";
				
				srcFolder = [srcFolder stringByAppendingPathComponent: [[[imagesArray lastObject] valueForKeyPath: @"series.study.name"] filenameString]];
				destFile = [destFile stringByAppendingPathComponent: [[[imagesArray lastObject] valueForKeyPath: @"series.study.name"] filenameString]];
				
				if (isMacOS)
					destFile = [destFile  stringByAppendingPathExtension: @"zip"];
				else
					destFile = [destFile  stringByAppendingPathExtension: @"osirixzip"];
				
				if (srcFolder)
					[[NSFileManager defaultManager] removeItemAtPath: srcFolder error: nil];
				
				if (destFile)
					[[NSFileManager defaultManager] removeItemAtPath: destFile error: nil];
				
				[[NSFileManager defaultManager] createDirectoryAtPath: srcFolder attributes: nil];
				
				if (lockReleased == NO)
				{
					[self.portal.dicomDatabase.managedObjectContext unlock];
					lockReleased = YES;
				}
				
				if (user.encryptedZIP.boolValue)
					[BrowserController encryptFiles: [imagesArray valueForKey: @"completePath"] inZIPFile: destFile password:user.password];
				else
					[BrowserController encryptFiles: [imagesArray valueForKey: @"completePath"] inZIPFile: destFile password: nil];
				
				data = [NSData dataWithContentsOfFile: destFile];
				
				if (srcFolder)
					[[NSFileManager defaultManager] removeItemAtPath: srcFolder error: nil];
				
				if (destFile)
					[[NSFileManager defaultManager] removeItemAtPath: destFile error: nil];
				
				if (data)
					err = NO;
				else
				{
					data = [NSData data];
					err = NO;
				}
			}
			@catch( NSException *e)
			{
				NSLog( @"**** web seriesAsZIP exception : %@", e);
			}
		}
	}
	
	*/
}

-(void)processImage {
	DicomSeries* series = [self series_requestedSeries];
	if (!series)
		return;
	
	NSArray* images = [series.images allObjects];
	DicomImage* dicomImage = images.count == 1 ? [images lastObject] : [images objectAtIndex:images.count/2];
	
	DCMPix* dcmPix = [[[DCMPix alloc] initWithPath:dicomImage.completePathResolved :0 :1 :nil :dicomImage.numberOfFrames.intValue/2 :dicomImage.series.id.intValue isBonjour:NO imageObj:dicomImage] autorelease];
	
	/*if (!dcmPix)
	{
		NSLog( @"****** dcmPix creation failed for file : %@", [im valueForKey:@"completePathResolved"]);
		float *imPtr = (float*)malloc( [[im valueForKey: @"width"] intValue] * [[im valueForKey: @"height"] intValue] * sizeof(float));
		for (int i = 0; i < dicomImage.width.intValue*dicomImage.height.intValue; i++)
			imPtr[i] = i;
		
		dcmPix = [[[DCMPix alloc] initWithData: imPtr :32 :[[dicomImage valueForKey: @"width"] intValue] :[[dicomImage valueForKey: @"height"] intValue] :0 :0 :0 :0 :0] autorelease];
	}*/
	
	if (!dcmPix)
		return;
	
	float curWW = 0;
	float curWL = 0;
	
	if (dicomImage.series.windowWidth) {
		curWW = dicomImage.series.windowWidth.floatValue;
		curWL = dicomImage.series.windowLevel.floatValue;
	}
	
	if (curWW != 0)
		[dcmPix checkImageAvailble:curWW :curWL];
	else [dcmPix checkImageAvailble:dcmPix.savedWW :dcmPix.savedWL];
	
	NSImage* image = [dcmPix image];
	
	float width = image.size.width;
	float height = image.size.height;
	
/*	int maxWidth = maxResolution, maxHeight = maxResolution;
	int minWidth = minResolution, minHeight = minResolution;
	
	BOOL resize = NO;
	
	if (width>maxWidth) {
		height =  height * maxWidth / width;
		width = maxWidth;
		resize = YES;
	}
	
	if (height>maxHeight) {
		width = width * maxHeight / height;
		height = maxHeight;
		resize = YES;
	}
	
	if (width < minWidth) {
		height = height * (float)minWidth / width;
		width = minWidth;
		resize = YES;
	}
	
	if (height < minHeight) {
		width = width * (float)minHeight / height;
		height = minHeight;
		resize = YES;
	}
	
	if (resize)
		image = [image imageByScalingProportionallyToSize:NSMakeSize(width, height)];*/
	
	if ([parameters objectForKey:@"previewForMovie"]) {
		[image lockFocus];
		
		NSImage* r = [NSImage imageNamed:@"PlayTemplate.png"];
		[r drawInRect:NSRectCenteredInRect(NSMakeRect(0,0,r.size.width,r.size.height), NSMakeRect(0,0,image.size.width,image.size.height)) fromRect:NSMakeRect(0,0,r.size.width,r.size.height) operation:NSCompositeSourceOver fraction:1.0];
		
		[image unlockFocus];
	}
	
	NSBitmapImageRep* imageRep = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
	
	NSDictionary *imageProps = [NSDictionary dictionaryWithObject: [NSNumber numberWithFloat: 0.8] forKey:NSImageCompressionFactor];
	if ([requestedPath.pathExtension isEqualToString:@"png"]){
		response.data = [imageRep representationUsingType:NSPNGFileType properties:imageProps];
		response.mimeType = @"image/png";
		
	} else if ([requestedPath.pathExtension isEqualToString:@"jpg"]) {
		response.data = [imageRep representationUsingType:NSJPEGFileType properties:imageProps];
		response.mimeType = @"image/jpeg";
	} // else NSLog( @"***** unknown path extension: %@", [fileURL pathExtension]);
}

-(void)processMovie {
	DicomSeries* series = [self series_requestedSeries];
	if (!series)
		return;
	
	response.data = [self produceMovieForSeries:series isiPhone:self.requestIsIOS fileURL:requestedPath];
	
	//if (data == nil || [data length] == 0)
	//	NSLog( @"****** movie data == nil");
}


@end




