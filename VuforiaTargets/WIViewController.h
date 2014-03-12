//
//  WIViewController.h
//  VuforiaTargets
//
//  Created by Paul Wood on 2/21/14.
//  Copyright (c) 2014 Walkin. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <EDStarRating/EDStarRating.h>

@interface WIViewController : UITableViewController <EDStarRatingProtocol>

@property (strong) NSMutableArray *imageTargets;

@end

@interface WITargetTableViewCell : UITableViewCell

extern NSString *const kWITargetTableViewCellReuseIdentifier;

@property (strong) NSArray *contentArray;
@property (weak) IBOutlet UIView *content;
@property (weak) IBOutlet UILabel *targetName;
@property (weak) IBOutlet EDStarRating *targetStarRating;
@property (weak) IBOutlet UIImageView *mainImage;
@property (weak) IBOutlet UIImageView *featureImage;

@end
