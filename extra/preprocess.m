function preprocess()
% PREPROCESS  Build vocabulary and compute histograms
%   PREPROCESS() download an image dataset into 'data/', VLFeat into
%   'vlfeat/', and precompute the histograms for the dataset.

  % --------------------------------------------------------------------
  %                                                      Download VLFeat
  % --------------------------------------------------------------------
  if ~exist('vlfeat', 'dir')
    from = 'http://www.vlfeat.org/download/vlfeat-0.9.15-bin.tar.gz' ;
    fprintf('Downloading vlfeat from %s\n', from) ;
    untar(from, 'data') ;
    movefile('data/vlfeat-0.9.15', 'vlfeat') ;
  end

  % --------------------------------------------------------------------
  %                                                      Setup Oxford 5k
  % --------------------------------------------------------------------
  imdb = setupOxford5kBase('data/oxbuild_images') ;
  for t = 3
    switch t
      case 1
        suffix = '100k_disc_hessian' ;
        numWords = 100e3 ;
        featureOpts = {'method', 'hessian', 'affineAdaptation', false, 'orientation', false} ;
      case 2
        suffix = '100k_odisc_hessian' ;
        numWords = 100e3 ;
        featureOpts = {'method', 'hessian', 'affineAdaptation', false, 'orientation', true} ;
      case 3
        suffix = '100k_ellipse_hessian' ;
        numWords = 100e3 ;
        featureOpts = {'method', 'hessian', 'affineAdaptation', true, 'orientation', false} ;
      case 4
        suffix = '100k_oellipse_hessian' ;
        numWords = 100e3 ;
        featureOpts = {'method', 'hessian', 'affineAdaptation', true, 'orientation', true} ;
    end
    setupOxford5k(imdb, suffix, numWords, featureOpts) ;
  end
end

% --------------------------------------------------------------------
function imdb = setupOxford5kBase(imPath)
% --------------------------------------------------------------------
  imdbPath = 'data/oxbuild_imdb.mat' ;
  if exist(imdbPath, 'file'), imdb = load(imdbPath) ; return ; end
  names = dir(fullfile(imPath, '*.jpg')) ;

  imdb.dir = imPath ;
  imdb.images.id = 1:numel(names) ;
  imdb.images.name = {names.name} ;
  save(imdbPath, '-STRUCT', 'imdb') ;

  for i = 1:numel(imdb.images.id)
    [~,postfixless{i}] = fileparts(imdb.images.name{i}) ;
  end
  function i = toindex(x)
    [~,i] = ismember(x,postfixless) ;
  end
  names = dir('data/oxbuild_gt/*_query.txt') ;
  names = {names.name} ;
  for i = 1:numel(names)
    base = names{i} ;
    [imageName,x0,y0,x1,y1] = textread(fullfile('data/oxbuild_gt/', base), '%s %f %f %f %f') ;
    name = base ;
    name = name(1:end-10) ;
    imageName = cell2mat(imageName) ;
    imageName = imageName(6:end) ;
    query(i).name = name ;
    query(i).imageName = imageName ;
    query(i).imageId = toindex(imageName) ;
    query(i).box = [x0;y0;x1;y1] ;
    query(i).good = toindex(textread(fullfile('data/oxbuild_gt/', sprintf('%s_good.txt',name)), '%s')) ;
    query(i).ok = toindex(textread(fullfile('data/oxbuild_gt/', sprintf('%s_ok.txt',name)), '%s')) ;
    query(i).junk = toindex(textread(fullfile('data/oxbuild_gt/', sprintf('%s_junk.txt',name)), '%s')) ;
  end
  save('data/oxbuild_query.mat', 'query') ;
end

% --------------------------------------------------------------------
function setupOxford5k(imdb, suffix, numWords, featureOpts)
% --------------------------------------------------------------------
  imdbPath = ['data/oxbuild_imdb_' suffix '.mat'] ;
  if exist(imdbPath, 'file'), return ; end
  imdb.featureOpts = featureOpts ;
  imdb.numWords = numWords ;

  % ------------------------------------------------------------------
  %                                      Compute the visual vocabulary
  % ------------------------------------------------------------------
  descrs = cell(1,numel(imdb.images.name)) ;
  numWordsPerImage = ceil(imdb.numWords * 10 / numel(imdb.images.name)) ;
  parfor i = 1:numel(imdb.images.name)
    fprintf('get features from %i, %s\n', i, imdb.images.name{i}) ;
    [~,descrs{i}] = getFeatures(imread(fullfile(imdb.dir, imdb.images.name{i})), imdb.featureOpts{:}) ;
    randn('state',i) ;
    descrs{i} = vl_colsubset(descrs{i},numWordsPerImage) ;
  end

  descrs = cat(2,descrs{:}) ;
  [imdb.vocab, imdb.kdtree] = annkmeans(descrs, imdb.numWords, ...
                                        'numTrees', 4, ...
                                        'maxNumComparisons', 1024, ...
                                        'maxNumIterations', 30, ...
                                        'tolerance', 1e-3, ...
                                        'verbose', true, ...
                                        'seed', 2) ;

  % --------------------------------------------------------------------
  %                                                 Compute the features
  % --------------------------------------------------------------------
  clear frames words ;
  parfor i = 1:numel(imdb.images.name)
    fprintf('get features from %i, %s\n', i, imdb.images.name{i}) ;
    [frames{i},descrs{i}] = getFeatures(imread(...
      fullfile(imdb.dir, imdb.images.name{i})), imdb.featureOpts{:}) ;
    frames{i} = single(frames{i}) ;
    words{i} = vl_kdtreequery(imdb.kdtree, imdb.vocab, descrs{i}, ...
                               'maxNumComparisons', 1024) ;
  end

  imdb.images.frames = frames ;
  imdb.images.words = words ;
  save(imdbPath, '-STRUCT', 'imdb') ;
end
